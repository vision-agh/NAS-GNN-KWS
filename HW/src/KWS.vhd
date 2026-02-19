library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

Library xpm;
use xpm.vcomponents.all;

entity KWS is
    Generic (   
        T_WIDTH     : INTEGER := 32;
        F_WIDTH     : INTEGER := 6;
        NUM_CHANNEL : integer := 64;
        WEIGHT      : integer := 32;
        DECAY_SHIFT : integer := 8;
        PRECISION_GEN  : integer := 8 ;
        CLS_NUM : integer := 11
    );
    Port (
        clock_200    : in std_logic;
        clock_48     : in std_logic;
        rst_ext      : in std_logic;

        in_t         : in STD_LOGIC_VECTOR(T_WIDTH-1  downto 0);
        in_f         : in STD_LOGIC_VECTOR(F_WIDTH downto 0);
        in_valid     : in STD_LOGIC;
        idx_time     : in STD_LOGIC_VECTOR(15 downto 0);

        cnn_valid    : out STD_LOGIC;
        cnn_conf     : out STD_LOGIC_VECTOR(PRECISION_GEN-1 downto 0);
        cnn_class    : out STD_LOGIC_VECTOR((PRECISION_GEN*CLS_NUM)-1 downto 0)
    );
end KWS;

architecture Behavioral of KWS is

    COMPONENT lif
        GENERIC (
            T_WIDTH     : integer;
            F_WIDTH     : integer;
            NUM_CHANNEL : integer;
            WEIGHT      : integer;
            DECAY_SHIFT : integer
        );
        PORT (
            clk        : in  std_logic;
            rst        : in  std_logic;
            in_req     : in  std_logic;
            in_t       : in  std_logic_vector(T_WIDTH-1 downto 0);
            in_f       : in  std_logic_vector(F_WIDTH downto 0);
            idx_time_in : in std_logic_vector(15 downto 0);
            
            out_valid  : out std_logic;
            out_t      : out std_logic_vector(T_WIDTH-1 downto 0);
            out_f      : out std_logic_vector(F_WIDTH-1 downto 0);
            out_p      : out std_logic;
            
            last_time_out : out std_logic_vector(T_WIDTH-1 downto 0);
            idx_time_out  : out std_logic_vector(15 downto 0)
        );
    END COMPONENT;

    COMPONENT fifo_generator_ok
      PORT (
        srst        : IN STD_LOGIC;
        wr_clk      : IN STD_LOGIC;
        rd_clk      : IN STD_LOGIC;
        din         : IN STD_LOGIC_VECTOR(39 DOWNTO 0);
        wr_en       : IN STD_LOGIC;
        rd_en       : IN STD_LOGIC;
        dout        : OUT STD_LOGIC_VECTOR(39 DOWNTO 0);
        full        : OUT STD_LOGIC;
        empty       : OUT STD_LOGIC;
        wr_rst_busy : OUT STD_LOGIC;
        rd_rst_busy : OUT STD_LOGIC 
      );
    END COMPONENT;

    COMPONENT gcnn_top
        PORT (
            clk         : in std_logic;
            reset       : in std_logic;
            t           : in std_logic_vector(T_WIDTH-1 downto 0);
            f           : in std_logic_vector(F_WIDTH-1 downto 0);
            p           : in std_logic;
            is_valid    : in std_logic;
            is_ready    : out std_logic;
            last_time   : in STD_LOGIC_VECTOR(T_WIDTH-1 downto 0);
            idx_time    : in STD_LOGIC_VECTOR(15 downto 0);
            out_valid   : out std_logic;
            out_conf    : out std_logic_vector(PRECISION_GEN-1 downto 0);
            out_cls     : out std_logic_vector((PRECISION_GEN*CLS_NUM)-1 downto 0)
        );
    END COMPONENT;

    signal lif_out_valid  : std_logic;
    signal lif_out_t      : std_logic_vector(T_WIDTH-1 downto 0);
    signal lif_out_f      : std_logic_vector(F_WIDTH-1 downto 0);
    signal lif_out_p      : std_logic;

    signal lif_last_time_48 : std_logic_vector(T_WIDTH-1 downto 0);
    signal lif_idx_time_48  : std_logic_vector(15 downto 0);

    signal fifo_din       : std_logic_vector(39 downto 0);
    signal fifo_wr_en     : std_logic;
    signal dout           : std_logic_vector(39 downto 0);
    signal empty          : std_logic;
    signal full           : std_logic;
    signal rd_en          : std_logic := '0';

    signal ready_r        : std_logic;
    signal valid_r        : std_logic := '0';
    signal t_r            : std_logic_vector(T_WIDTH-1 downto 0);
    signal f_r            : std_logic_vector(F_WIDTH-1 downto 0);
    signal p_r            : std_logic;
    
    signal synced_last_time : std_logic_vector(T_WIDTH-1 downto 0); 
    signal synced_idx_time  : std_logic_vector(15 downto 0);

    signal cdc_src_in   : std_logic_vector(T_WIDTH + 15 downto 0);
    signal cdc_dest_out : std_logic_vector(T_WIDTH + 15 downto 0);
    signal src_send     : std_logic := '0';
    signal src_rcv      : std_logic;
    signal dest_req     : std_logic;
    signal prev_idx_48  : std_logic_vector(15 downto 0) := (others => '0');
    signal initial_sync_done : std_logic := '0';
    
begin

    lif_inst : lif
    GENERIC MAP (
        T_WIDTH     => T_WIDTH,
        F_WIDTH     => F_WIDTH,
        NUM_CHANNEL => NUM_CHANNEL,
        WEIGHT      => WEIGHT,
        DECAY_SHIFT => DECAY_SHIFT
    )
    PORT MAP (
        clk         => clock_48,
        rst         => rst_ext,
        in_req      => in_valid,
        in_t        => in_t,
        in_f        => in_f,
        idx_time_in => idx_time,
        
        out_valid   => lif_out_valid,
        out_t       => lif_out_t,
        out_f       => lif_out_f,
        out_p       => lif_out_p,
        
        last_time_out => lif_last_time_48,
        idx_time_out  => lif_idx_time_48
    );

    cdc_src_in <= lif_last_time_48 & lif_idx_time_48;

process(clock_48, rst_ext)
    begin
        if rst_ext = '1' then
            src_send          <= '0';
            prev_idx_48       <= (others => '0');
            initial_sync_done <= '0';
        elsif rising_edge(clock_48) then
            src_send <= '0';
            if src_rcv = '0' then
                if (lif_idx_time_48 /= prev_idx_48) or (initial_sync_done = '0') then
                    src_send          <= '1';
                    prev_idx_48       <= lif_idx_time_48;
                    initial_sync_done <= '1';
                end if;
            end if;
        end if;
    end process;

    xpm_cdc_handshake_inst : xpm_cdc_handshake
    generic map (
        DEST_EXT_HSK   => 0,
        DEST_SYNC_FF   => 4,
        INIT_SYNC_FF   => 0,
        SIM_ASSERT_CHK => 0,
        SRC_SYNC_FF    => 4,
        WIDTH          => T_WIDTH + 16
    )
    port map (
        src_clk  => clock_48,
        src_in   => cdc_src_in,
        src_send => src_send,
        src_rcv  => src_rcv,
        dest_clk => clock_200,
        dest_out => cdc_dest_out,
        dest_req => dest_req,
        dest_ack => '0'
    );

    process(clock_200)
    begin
        if rising_edge(clock_200) then
            if dest_req = '1' then
                synced_last_time <= cdc_dest_out(T_WIDTH + 15 downto 16);
                synced_idx_time  <= cdc_dest_out(15 downto 0);
            end if;
        end if;
    end process;

    fifo_wr_en <= lif_out_valid; 
    fifo_din   <= lif_out_t & lif_out_f & lif_out_p & '0'; 

    FIFO_CDC : fifo_generator_ok
    PORT MAP (
        srst        => rst_ext,
        wr_clk      => clock_48,
        rd_clk      => clock_200,
        din         => fifo_din,
        wr_en       => fifo_wr_en,
        rd_en       => rd_en,
        dout        => dout,
        full        => full,
        empty       => empty,
        wr_rst_busy => open,
        rd_rst_busy => open
    );

    rd: process(clock_200, rst_ext)
    begin
        if rst_ext = '1' then
            rd_en <= '0';
        elsif rising_edge(clock_200) then
            rd_en <= '0';
            if empty = '0' then
                if ready_r = '1' then
                    rd_en <= '1';
                end if;
            end if;
        end if;
    end process;
    
    unpack: process(clock_200, rst_ext)
        variable rd_en_d1 : std_logic := '0';
    begin
        if rst_ext = '1' then
            valid_r <= '0';
            t_r     <= (others => '0');
            f_r     <= (others => '0');
            p_r     <= '0'; 
            rd_en_d1 := '0';
        elsif rising_edge(clock_200) then
            valid_r <= rd_en_d1;
            
            if rd_en_d1 = '1' then
                f_r <= dout(F_WIDTH+1 downto 2);
                t_r <= dout(39 downto F_WIDTH+2);
                p_r <= dout(1);
            end if;
            
            rd_en_d1 := rd_en;
        end if;
    end process;

    gcnn_inst : gcnn_top
    PORT MAP (
        clk        => clock_200,
        reset      => rst_ext,
        t          => t_r,
        f          => f_r,
        p          => p_r,
        is_valid   => valid_r,
        is_ready   => ready_r,
        out_valid  => cnn_valid,
        
        last_time  => synced_last_time,
        idx_time   => synced_idx_time,
        
        out_conf   => cnn_conf,
        out_cls    => cnn_class
    );

end Behavioral;