library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity timestamp_gen is
    Generic ( 
        T_WIDTH : INTEGER := 32;
        F_WIDTH : INTEGER := 7
    );
    Port (
        clk       : in std_logic;
        rst       : in std_logic;
        
        -- AER Interface (Input)
        AER_DATA  : in STD_LOGIC_VECTOR(6 downto 0);
        AER_REQ   : in STD_LOGIC;
        AER_ACK   : out STD_LOGIC;
        
        -- Event Interface (Output to KWS)
        out_t     : out STD_LOGIC_VECTOR(T_WIDTH-1 downto 0);
        out_f     : out STD_LOGIC_VECTOR(F_WIDTH-1 downto 0);
        out_valid : out STD_LOGIC;
        KWS_busy : in STD_LOGIC -- from KWS
    );
end timestamp_gen;

architecture Behavioral of timestamp_gen is

    constant TS_DIV       : integer := 48;
    signal timer_active   : std_logic := '0';
    signal t_counter      : unsigned(T_WIDTH-1 downto 0) := (others => '0');
    signal ts_div_count   : unsigned(5 downto 0)         := (others => '0');
    
    signal aer_ack_int    : std_logic := '0';
    signal aer_state      : std_logic_vector(1 downto 0) := "00";

begin


    ts: process(clk, rst)
    begin
        if rst = '1' then
            ts_div_count <= (others => '0');
            t_counter    <= (others => '0');
            timer_active <= '0';   
        elsif rising_edge(clk) then
            if timer_active = '0' and AER_REQ = '1' then
                timer_active <= '1';
            end if;
            if timer_active = '1' then
                if ts_div_count = TS_DIV - 1 then
                    ts_div_count <= (others => '0');
                    t_counter    <= t_counter + 1;
                else
                    ts_div_count <= ts_div_count + 1;
                end if;
            end if;
        end if;
    end process;


    aer_handshake: process(clk, rst)
    begin
        if rst = '1' then
            aer_state   <= "00";
            aer_ack_int <= '0';
            out_valid   <= '0';
            out_t       <= (others => '0');
            out_f       <= (others => '0');
        elsif rising_edge(clk) then
            out_valid <= '0';
            
            case aer_state is
                when "00" => 
                    if KWS_busy = '0' then 
                        aer_ack_int <= '1'; 
                        aer_state   <= "01";
                    end if;
                when "01" => 
                    if AER_REQ = '1' then
                        out_t       <= std_logic_vector(t_counter);
                        out_f       <= AER_DATA;
                        out_valid   <= '1';
                        
                        aer_ack_int <= '0'; 
                        aer_state   <= "10";
                    end if;
                when "10" => 
                    if AER_REQ = '0' then
                        aer_state <= "00";
                    end if;
                when others =>
                    aer_state <= "00";
            end case;
        end if;
    end process;

    AER_ACK <= aer_ack_int;

end Behavioral;