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
        
        AER_DATA  : in STD_LOGIC_VECTOR(6 downto 0);
        AER_REQ   : in STD_LOGIC;
        AER_ACK   : out STD_LOGIC;
        
        out_t     : out STD_LOGIC_VECTOR(T_WIDTH-1 downto 0);
        out_f     : out STD_LOGIC_VECTOR(F_WIDTH-1 downto 0);
        out_valid : out STD_LOGIC

    );
end timestamp_gen;

architecture Behavioral of timestamp_gen is

    constant TS_DIV       : integer := 48;
    signal timer_active   : std_logic := '0';
    signal t_counter      : unsigned(T_WIDTH-1 downto 0) := (others => '0');
    signal ts_div_count   : unsigned(5 downto 0)         := (others => '0');

    signal req_sync_reg   : std_logic_vector(1 downto 0) := "00";
    signal req_synced     : std_logic;
    signal req_prev       : std_logic := '0';
    signal req_rising     : std_logic;
    
    signal ack_reg        : std_logic := '0';

begin


    ts: process(clk, rst)
    begin
        if rst = '1' then
            ts_div_count <= (others => '0');
            t_counter    <= (others => '0');
            timer_active <= '0';   
        elsif rising_edge(clk) then
            if timer_active = '0' and req_synced = '1' then
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
    
    req_synced <= req_sync_reg(1);
    req_rising <= '1' when (req_synced = '1' and req_prev = '0') else '0';

    aer_proc: process(clk, rst)
    begin
        if rst = '1' then
            req_sync_reg <= "00";
            req_prev     <= '0';
            ack_reg      <= '0';
            out_valid    <= '0';
            out_t        <= (others => '0');
            out_f        <= (others => '0');
        elsif rising_edge(clk) then
            req_sync_reg <= req_sync_reg(0) & AER_REQ;
            req_prev     <= req_synced;
            out_valid <= '0';
            
            if req_rising = '1' then
                out_t     <= std_logic_vector(t_counter);
                out_f     <= AER_DATA; 
                out_valid <= '1';
            end if;
            ack_reg <= req_synced;

        end if;
    end process;

    AER_ACK <= ack_reg;

end Behavioral;