library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
Library xpm;
use xpm.vcomponents.all;

entity aer_cdc_bridge is
    Port (
        rst_n        : in  std_logic;
        
        -- Write side: 48 MHz (from NAS)
        clk_nas      : in  std_logic;
        nas_req_n    : in  std_logic;
        nas_ack_n    : out std_logic;
        nas_data     : in  std_logic_vector(7 downto 0);
        
        -- Read side: 100.8 MHz (to OKAERTool)
        clk_ok       : in  std_logic;
        ok_req_n     : out std_logic;
        ok_ack_n     : in  std_logic;
        ok_data      : out std_logic_vector(7 downto 0)
    );
end aer_cdc_bridge;

architecture Behavioral of aer_cdc_bridge is

    -- FIFO Signals
    signal fifo_din   : std_logic_vector(7 downto 0);
    signal fifo_dout  : std_logic_vector(7 downto 0);
    signal fifo_wren  : std_logic;
    signal fifo_rden  : std_logic;
    signal fifo_full  : std_logic;
    signal fifo_empty : std_logic;
    
    -- Write FSM (48 MHz)
    type wr_state_type is (S_IDLE, S_ACK_LOW, S_ACK_HIGH);
    signal wr_state : wr_state_type := S_IDLE;

    -- Read FSM (100.8 MHz)
    type rd_state_type is (S_IDLE, S_LATCH_DATA, S_REQ_LOW, S_WAIT_ACK_HIGH);
    signal rd_state : rd_state_type := S_IDLE;

begin

    xpm_fifo_async_inst : xpm_fifo_async
    generic map (
        FIFO_MEMORY_TYPE    => "auto",
        FIFO_WRITE_DEPTH    => 2048,
        FIFO_READ_LATENCY   => 1,
        WRITE_DATA_WIDTH    => 8,
        READ_DATA_WIDTH     => 8,
        CDC_SYNC_STAGES     => 4,
        USE_ADV_FEATURES    => "0000"
    )
    port map (
        rst           => not rst_n,
        wr_clk        => clk_nas,
        wr_en         => fifo_wren,
        din           => fifo_din,
        full          => fifo_full,
        rd_clk        => clk_ok,
        rd_en         => fifo_rden,
        dout          => fifo_dout,
        empty         => fifo_empty,
        sleep         => '0',
        injectsbiterr => '0',
        injectdbiterr => '0'
    );

    ok_data <= fifo_dout;

    -- =======================================================
    -- Write FSM (48 MHz): AER receiver
    -- =======================================================
    process(clk_nas, rst_n)
    begin
        if rst_n = '0' then
            wr_state  <= S_IDLE;
            nas_ack_n <= '1';
            fifo_wren <= '0';
        elsif rising_edge(clk_nas) then
            fifo_wren <= '0';
            
            case wr_state is
                when S_IDLE =>
                    if nas_req_n = '0' and fifo_full = '0' then
                        fifo_din  <= nas_data;
                        fifo_wren <= '1';
                        wr_state  <= S_ACK_LOW;
                    end if;
                    
                when S_ACK_LOW =>
                    nas_ack_n <= '0';
                    if nas_req_n = '1' then
                        wr_state <= S_ACK_HIGH;
                    end if;
                    
                when S_ACK_HIGH =>
                    nas_ack_n <= '1';
                    wr_state  <= S_IDLE;
            end case;
        end if;
    end process;

    -- =======================================================
    -- Read FSM (100.8 MHz): AER sender
    -- =======================================================
    process(clk_ok, rst_n)
    begin
        if rst_n = '0' then
            rd_state  <= S_IDLE;
            ok_req_n  <= '1';
            fifo_rden <= '0';
        elsif rising_edge(clk_ok) then
            fifo_rden <= '0'; -- Pulse by default
            
            case rd_state is
                when S_IDLE =>
                    if fifo_empty = '0' then
                        fifo_rden <= '1';
                        rd_state  <= S_LATCH_DATA;
                    end if;
                    
                when S_LATCH_DATA =>
                    rd_state <= S_REQ_LOW;
                    
                when S_REQ_LOW =>
                    ok_req_n <= '0';
                    if ok_ack_n = '0' then
                        rd_state <= S_WAIT_ACK_HIGH;
                    end if;
                    
                when S_WAIT_ACK_HIGH =>
                    ok_req_n <= '1';
                    if ok_ack_n = '1' then
                        rd_state <= S_IDLE;
                    end if;
            end case;
        end if;
    end process;

end Behavioral;