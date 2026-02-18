library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity timestamp_gen is
    Generic ( 
        T_WIDTH : INTEGER := 32;
        F_WIDTH : INTEGER := 7
    );
    Port (
        clk        : in std_logic;
        rst        : in std_logic;
        
        AER_DATA   : in STD_LOGIC_VECTOR(6 downto 0);
        AER_REQ    : in STD_LOGIC;
        AER_ACK    : out STD_LOGIC;
        
        out_t      : out STD_LOGIC_VECTOR(T_WIDTH-1 downto 0);
        out_f      : out STD_LOGIC_VECTOR(F_WIDTH-1 downto 0);
        out_valid  : out STD_LOGIC;
        
        -- last_time removed
        idx_time   : out STD_LOGIC_VECTOR(15 downto 0)
    );
end timestamp_gen;

architecture Behavioral of timestamp_gen is

    constant TS_DIV       : integer := 48;
    constant CYCLES_10MS  : integer := 480000;

    signal timer_active   : std_logic := '0';
    signal t_counter      : unsigned(T_WIDTH-1 downto 0) := (others => '0');
    signal ts_div_count   : unsigned(5 downto 0)         := (others => '0');

    signal req_sync_reg   : std_logic_vector(1 downto 0) := "11";
    signal req_synced     : std_logic;
    signal req_prev       : std_logic := '1';
    signal req_falling    : std_logic;
    
    signal cnt_10ms       : integer range 0 to CYCLES_10MS := 0;
    signal window_idx_counter : unsigned(15 downto 0) := (others => '0');

begin

    ts: process(clk, rst)
    begin
        if rst = '1' then
            ts_div_count <= (others => '0');
            t_counter    <= (others => '0');
            timer_active <= '0';    
        elsif rising_edge(clk) then
            if timer_active = '0' and req_synced = '0' then
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
    req_falling <= '1' when (req_synced = '0' and req_prev = '1') else '0';

    aer_proc: process(clk, rst)
    begin
        if rst = '1' then
            req_sync_reg <= "11";
            req_prev     <= '1';
            out_valid    <= '0';
            out_t        <= (others => '0');
            out_f        <= (others => '0');
        elsif rising_edge(clk) then
            req_sync_reg <= req_sync_reg(0) & AER_REQ;
            req_prev     <= req_synced;
            out_valid    <= '0';
            
            if req_falling = '1' then
                out_t <= std_logic_vector(t_counter);
                out_f(6 downto 0) <= AER_DATA;
                out_f(F_WIDTH-1 downto 7) <= (others => '0'); 
                out_valid <= '1';
            end if;
        end if;
    end process;

    AER_ACK <= req_synced;

    process_10ms: process(clk, rst)
    begin
        if rst = '1' then
            cnt_10ms           <= 0;
            window_idx_counter <= (others => '0');
            idx_time           <= (others => '0');
        elsif rising_edge(clk) then
            
            if cnt_10ms = CYCLES_10MS - 1 then
                cnt_10ms <= 0;
                window_idx_counter <= window_idx_counter + 1;
                idx_time <= std_logic_vector(window_idx_counter);
            else
                cnt_10ms <= cnt_10ms + 1;
            end if;
            
        end if;
    end process;

end Behavioral;