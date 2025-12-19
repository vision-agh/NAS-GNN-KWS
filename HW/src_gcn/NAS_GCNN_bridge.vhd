
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity NAS_GCNN_bridge is
    Generic (   
        T_WIDTH : INTEGER := 32;
        F_WIDTH : INTEGER := 7
    );
    Port (
        clock_200    : in std_logic;
        clock_48     : in std_logic;
        rst_ext      : in std_logic;

        --AER I/F
        AER_DATA_OUT : in STD_LOGIC_VECTOR(6 downto 0);
        AER_REQ      : in STD_LOGIC;
        AER_ACK      : out  STD_LOGIC;
        
        -- GCNN I/F
        t            : out STD_LOGIC_VECTOR(T_WIDTH-1  downto 0);
        f            : out STD_LOGIC_VECTOR(F_WIDTH-1 downto 0);
        is_valid     : out STD_LOGIC
    );
end NAS_GCNN_bridge;

architecture Behavioral of NAS_GCNN_bridge is

COMPONENT fifo_generator_1
  PORT (
    srst : IN STD_LOGIC;
    wr_clk : IN STD_LOGIC;
    rd_clk : IN STD_LOGIC;
    din : IN STD_LOGIC_VECTOR(39 DOWNTO 0);
    wr_en : IN STD_LOGIC;
    rd_en : IN STD_LOGIC;
    dout : OUT STD_LOGIC_VECTOR(39 DOWNTO 0);
    full : OUT STD_LOGIC;
    empty : OUT STD_LOGIC;
    wr_rst_busy : OUT STD_LOGIC;
    rd_rst_busy : OUT STD_LOGIC 
  );
END COMPONENT;

constant TS_DIV     : integer := 48;
signal timer_active : std_logic := '0';
-- AER domain
signal t_counter      : unsigned(T_WIDTH-1 downto 0) := (others => '0');
signal ts_div_count   : unsigned(5 downto 0)         := (others => '0');
signal wr_rst_active  : std_logic;
signal wr_en          : std_logic := '0';
signal fifo_din       : std_logic_vector(39 downto 0);
signal aer_ack_int    : std_logic := '0';
signal aer_state      : std_logic_vector(1 downto 0) := "00";

-- GCNN domain
signal valid_r        : std_logic := '0';
signal t_r            : std_logic_vector(T_WIDTH-1 downto 0);
signal f_r            : std_logic_vector(F_WIDTH-1 downto 0);

-- FIFO signals
signal dout           : std_logic_vector(39 downto 0);
signal empty          : std_logic;
signal full           : std_logic;
signal wr_rst_busy    : std_logic;
signal rd_rst_busy    : std_logic;
signal rd_en          : std_logic := '0';

begin

-- timestamp process
ts: process(clock_48, rst_ext)
begin
    if rst_ext = '1' then
        ts_div_count <= (others => '0');
        t_counter    <= (others => '0');
        timer_active <= '0';   
    elsif rising_edge(clock_48) then
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
    
aer_handshake: process(clock_48, rst_ext)
begin
    if rst_ext = '1' then
        aer_state <= "00";
        aer_ack_int <= '0';
        wr_en <= '0';
    elsif rising_edge(clock_48) then
        wr_en <= '0';
        case aer_state is
            when "00" =>
                if full = '0' and wr_rst_busy = '0' then
                    aer_ack_int <= '1';
                    aer_state   <= "01";
                end if;
            when "01" =>
                if AER_REQ = '1' then
                    fifo_din <= std_logic_vector(t_counter) & AER_DATA_OUT & '1'; -- timestamp +  data_out + is_valid
                    wr_en    <= '1';
                    aer_ack_int <= '0';
                    aer_state <= "10";
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

rd: process(clock_200, rst_ext)
begin
    if rst_ext = '1' then
        rd_en <= '0';

    elsif rising_edge(clock_200) then
        if empty = '0' and rd_rst_busy = '0' then
            rd_en <= '1';
        else
            rd_en <= '0';
        end if;
    end if;
end process;

unpack_to_GCNN: process(clock_200, rst_ext)
begin
    if rst_ext = '1' then
        valid_r <= '0';
    elsif rising_edge(clock_200) then
        if rd_en = '1' then
            valid_r <= dout(0);
            f_r     <= dout(F_WIDTH downto 1);
            t_r     <= dout(39 downto F_WIDTH+1);
        else
            valid_r <= '0';
        end if;
    end if;
end process;

t        <= t_r;
f        <= f_r;
is_valid <= valid_r;
        
FIFO_CDC : fifo_generator_1
  PORT MAP (
    srst => rst_ext,
    wr_clk => clock_48,
    rd_clk => clock_200,
    din => fifo_din,
    wr_en => wr_en,
    rd_en => rd_en,
    dout => dout,
    full => full,
    empty => empty,
    wr_rst_busy => wr_rst_busy,
    rd_rst_busy => rd_rst_busy
  );
  

end Behavioral;
