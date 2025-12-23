library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity KWS is
    Generic (   
        T_WIDTH     : INTEGER := 32;
        F_WIDTH     : INTEGER := 7;
        THROUGHPUT  : INTEGER := 400;
        NUM_CHANNEL : integer := 128;
<<<<<<< HEAD
<<<<<<< HEAD
        WEIGHT      : integer := 32;
        DECAY_SHIFT : integer := 8;
=======
        WEIGHT      : integer := 1;
        DECAY_SHIFT : integer := 4;
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
        WEIGHT      : integer := 32;
        DECAY_SHIFT : integer := 8;
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
        PRECISION_GEN  : integer := 8 
    );
    Port (
        clock_200    : in std_logic;
        clock_48     : in std_logic;
        rst_ext      : in std_logic;

<<<<<<< HEAD
<<<<<<< HEAD
        -- Input Interface
        in_t         : in STD_LOGIC_VECTOR(T_WIDTH-1  downto 0);
        in_f         : in STD_LOGIC_VECTOR(F_WIDTH-1 downto 0);
        in_valid     : in STD_LOGIC;

        -- GCNN Output
        cnn_valid    : out STD_LOGIC;
        cnn_conf     : out STD_LOGIC_VECTOR(PRECISION_GEN-1 downto 0);
        cnn_class    : out STD_LOGIC_VECTOR((8*20)-1 downto 0)


--         debug_valid  : out std_logic;
--         debug_t      : out std_logic_vector(T_WIDTH-1 downto 0);
--         debug_f      : out std_logic_vector(F_WIDTH-1 downto 0)
=======
        -- Input Interface (from timestamp_gen)
=======
        -- Input Interface
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
        in_t         : in STD_LOGIC_VECTOR(T_WIDTH-1  downto 0);
        in_f         : in STD_LOGIC_VECTOR(F_WIDTH-1 downto 0);
        in_valid     : in STD_LOGIC;

        -- GCNN Output
        cnn_valid    : out STD_LOGIC;
        cnn_conf     : out STD_LOGIC_VECTOR(PRECISION_GEN-1 downto 0);
        cnn_class    : out STD_LOGIC_VECTOR((8*20)-1 downto 0)
<<<<<<< HEAD
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======


--         debug_valid  : out std_logic;
--         debug_t      : out std_logic_vector(T_WIDTH-1 downto 0);
--         debug_f      : out std_logic_vector(F_WIDTH-1 downto 0)
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    );
end KWS;

architecture Behavioral of KWS is

    -- 1. LIF Filter
    COMPONENT lif
        GENERIC (
            T_WIDTH     : integer;
            F_WIDTH     : integer;
            NUM_CHANNEL : integer;
            WEIGHT      : integer;
            DECAY_SHIFT : integer
        );
        PORT (
            clk       : in  std_logic;
            rst       : in  std_logic;
            in_req    : in  std_logic;
            in_t      : in  std_logic_vector(T_WIDTH-1 downto 0);
            in_f      : in  std_logic_vector(F_WIDTH-1 downto 0);
<<<<<<< HEAD
<<<<<<< HEAD
=======
            busy      : out std_logic;
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
            out_valid : out std_logic;
            out_t     : out std_logic_vector(T_WIDTH-1 downto 0);
            out_f     : out std_logic_vector(F_WIDTH-1 downto 0)
        );
    END COMPONENT;

    -- 2. FIFO 48Mhz -> 200Mhz
    COMPONENT fifo_generator_1
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

    -- 3. GCNN top
    COMPONENT gcnn_top
        PORT (
            clk       : in std_logic;
            reset     : in std_logic;
            t         : in std_logic_vector(T_WIDTH-1 downto 0);
            f         : in std_logic_vector(F_WIDTH-1 downto 0);
            is_valid  : in std_logic;
<<<<<<< HEAD
<<<<<<< HEAD
=======

>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
            out_valid : out std_logic;
            out_conf  : out std_logic_vector(PRECISION_GEN-1 downto 0);
            out_cls   : out std_logic_vector((8*20)-1 downto 0)
        );
    END COMPONENT;

<<<<<<< HEAD
<<<<<<< HEAD
=======
    -- LIF signals
    signal lif_busy       : std_logic;
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    signal lif_out_valid  : std_logic;
    signal lif_out_t      : std_logic_vector(T_WIDTH-1 downto 0);
    signal lif_out_f      : std_logic_vector(F_WIDTH-1 downto 0);

<<<<<<< HEAD
<<<<<<< HEAD
=======
    -- FIFO signals
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    signal fifo_din       : std_logic_vector(39 downto 0);
    signal fifo_wr_en     : std_logic;
    signal dout           : std_logic_vector(39 downto 0);
    signal empty          : std_logic;
    signal full           : std_logic;
    signal wr_rst_busy    : std_logic;
    signal rd_rst_busy    : std_logic;
    signal rd_en          : std_logic := '0';

<<<<<<< HEAD
<<<<<<< HEAD
=======
    -- Output of FIFO -> Input of GCNN
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    signal valid_r        : std_logic := '0';
    signal t_r            : std_logic_vector(T_WIDTH-1 downto 0);
    signal f_r            : std_logic_vector(F_WIDTH-1 downto 0);

    signal read_timer     : integer range 0 to THROUGHPUT := 0;

begin

<<<<<<< HEAD
<<<<<<< HEAD
=======
    out_busy <= lif_busy or wr_rst_busy;

    -------------------------------------------------------------------------
    -- LIF FILTER INSTANCE (Clock Domain: 48 MHz)
    -------------------------------------------------------------------------
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    lif_inst : lif
    GENERIC MAP (
        T_WIDTH     => T_WIDTH,
        F_WIDTH     => F_WIDTH,
        NUM_CHANNEL => NUM_CHANNEL,
        WEIGHT      => WEIGHT,
        DECAY_SHIFT => DECAY_SHIFT
    )
    PORT MAP (
        clk       => clock_48,
        rst       => rst_ext,
        in_req    => in_valid,
        in_t      => in_t,
        in_f      => in_f,
<<<<<<< HEAD
<<<<<<< HEAD
=======
        busy      => lif_busy,
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
        out_valid => lif_out_valid,
        out_t     => lif_out_t,
        out_f     => lif_out_f
    );

<<<<<<< HEAD
<<<<<<< HEAD
    fifo_wr_en <= lif_out_valid; 
    fifo_din   <= lif_out_t & lif_out_f & '0'; 

    FIFO_CDC : fifo_generator_1
    PORT MAP (
=======
    -------------------------------------------------------------------------
    -- FIFO INSTANCE (CDC: 48 MHz -> 200 MHz)
    -------------------------------------------------------------------------
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    fifo_wr_en <= lif_out_valid; 
    fifo_din   <= lif_out_t & lif_out_f & '0'; 

    FIFO_CDC : fifo_generator_1
<<<<<<< HEAD
      PORT MAP (
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
    PORT MAP (
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
        srst        => rst_ext,
        wr_clk      => clock_48,
        rd_clk      => clock_200,
        din         => fifo_din,
        wr_en       => fifo_wr_en,
        rd_en       => rd_en,
        dout        => dout,
        full        => full,
        empty       => empty,
        wr_rst_busy => wr_rst_busy,
        rd_rst_busy => rd_rst_busy
<<<<<<< HEAD
<<<<<<< HEAD
    );

=======
      );

    -------------------------------------------------------------------------
    -- READ SIDE LOGIC (Clock Domain: 200 MHz)
    -------------------------------------------------------------------------
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
    );

>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    rd: process(clock_200, rst_ext)
    begin
        if rst_ext = '1' then
            rd_en      <= '0';
            read_timer <= 0;
        elsif rising_edge(clock_200) then
            rd_en <= '0';
<<<<<<< HEAD
<<<<<<< HEAD
=======

>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
            if read_timer < THROUGHPUT then
                read_timer <= read_timer + 1;
            end if;

            if empty = '0' and rd_rst_busy = '0' then
                if read_timer >= THROUGHPUT then
                    rd_en      <= '1';
                    read_timer <= 0; 
                end if;
            end if;
        end if;
    end process;
<<<<<<< HEAD
<<<<<<< HEAD
    
    unpack: process(clock_200, rst_ext)
        variable rd_en_d1 : std_logic := '0';
=======

    unpack_to_GCNN_input: process(clock_200, rst_ext)
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
    
    unpack: process(clock_200, rst_ext)
        variable rd_en_d1 : std_logic := '0';
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    begin
        if rst_ext = '1' then
            valid_r <= '0';
            t_r     <= (others => '0');
            f_r     <= (others => '0');
<<<<<<< HEAD
<<<<<<< HEAD
            rd_en_d1 := '0';
        elsif rising_edge(clock_200) then
            valid_r <= rd_en_d1;
            
            if rd_en_d1 = '1' then
                f_r <= dout(F_WIDTH downto 1);
                t_r <= dout(39 downto F_WIDTH+1);
            end if;
            
            rd_en_d1 := rd_en;
        end if;
    end process;

--     debug_valid <= valid_r;
--     debug_t     <= t_r;
--     debug_f     <= f_r;

=======
=======
            rd_en_d1 := '0';
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
        elsif rising_edge(clock_200) then
            valid_r <= rd_en_d1;
            
            if rd_en_d1 = '1' then
                f_r <= dout(F_WIDTH downto 1);
                t_r <= dout(39 downto F_WIDTH+1);
            end if;
            
            rd_en_d1 := rd_en;
        end if;
    end process;

<<<<<<< HEAD
    
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
--     debug_valid <= valid_r;
--     debug_t     <= t_r;
--     debug_f     <= f_r;

>>>>>>> 7831012 (HW: modify KWS architecture for testing)
    gcnn_inst : gcnn_top
    PORT MAP (
        clk       => clock_200,
        reset     => rst_ext,
        t         => t_r,
        f         => f_r,
        is_valid  => valid_r,
<<<<<<< HEAD
<<<<<<< HEAD
=======
        
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
        out_valid => cnn_valid,
        out_conf  => cnn_conf,
        out_cls   => cnn_class
    );

end Behavioral;