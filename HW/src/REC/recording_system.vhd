library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity recording_system is
    Port (
        i2s_bclk     : in    std_logic;
        i2s_d_in     : in    std_logic;
        i2s_lr       : in    std_logic;
        okUH         : in    std_logic_vector(4 downto 0);
        okHU         : out   std_logic_vector(2 downto 0);
        okUHU        : inout std_logic_vector(31 downto 0);
        okAA         : inout std_logic;
        leds         : out   std_logic_vector(7 downto 0);
        
        out_data     : out   std_logic_vector(15 downto 0);
        out_req_n    : out   std_logic;
        out_ack_n    : in    std_logic
    );
end recording_system;

architecture Behavioral of recording_system is
    signal ok_port_a_data : std_logic_vector(7 downto 0);
    signal ok_port_a_req  : std_logic;
    signal ok_port_a_ack  : std_logic;
    signal sys_clk          : std_logic;
    signal clk_48mhz        : std_logic;
    signal nas_aer_data     : std_logic_vector(15 downto 0);
    signal nas_aer_req      : std_logic;
    signal port_a_ack_n     : std_logic;
    signal clk_locked       : std_logic;
    
    signal sys_rst_n        : std_logic;


    component clk_wiz_0
        port (
            clk_out1  : out    std_logic;
            resetn     : in     std_logic;
            locked    : out    std_logic;
            clk_in1   : in     std_logic
        );
    end component;

begin
    inst_cdc_bridge : entity work.aer_cdc_bridge
        port map (
            rst_n     => sys_rst_n,
    
            -- 48 MHz side (NAS outputs)
            clk_nas   => clk_48mhz,
            nas_req_n => nas_aer_req,
            nas_ack_n => port_a_ack_n,
            nas_data  => nas_aer_data(7 downto 0),
    
            -- 100.8 MHz side (OKAERTool inputs)
            clk_ok    => sys_clk,
            ok_req_n  => ok_port_a_req,
            ok_ack_n  => ok_port_a_ack,
            ok_data   => ok_port_a_data
        );

    inst_clk_wiz : clk_wiz_0
        port map (
            clk_out1 => clk_48mhz,
            resetn    => sys_rst_n,
            locked   => clk_locked,
            clk_in1  => sys_clk
        );

    inst_okt_top : entity work.okt_top
        port map (
            rst_ext_n    => '1', 
            clock        => sys_clk,
            
            -- software reset triggered by Opal Kelly Python API
            rst_sw_n     => sys_rst_n, 
            
            okUH         => okUH,
            okHU         => okHU,
            okUHU        => okUHU,
            okAA         => okAA,
            
            port_a_data  => ok_port_a_data, 
            port_a_req_n => ok_port_a_req,
            port_a_ack_n => ok_port_a_ack,
            
            port_b_data  => (others => '0'),
            port_b_req_n => '1',
            port_b_ack_n => open,
            port_c_data  => (others => '0'),
            port_c_req_n => '1',
            port_c_ack_n => open,
            
            out_data     => out_data,
            out_req_n    => out_req_n,
            out_ack_n    => out_ack_n,
            config_data  => open,
            config_addr  => open,
            config_en    => open,    
            leds         => open
        );
        
    inst_nas : entity work.OpenNas_Parallel_MONO_32ch
        port map (
            clock        => clk_48mhz,
            rst_ext      => sys_rst_n, 
            
            i2s_bclk     => i2s_bclk,
            i2s_d_in     => i2s_d_in,
            i2s_lr       => i2s_lr,
            AER_DATA_OUT => nas_aer_data,
            AER_REQ      => nas_aer_req,
            AER_ACK      => port_a_ack_n
        );


end Behavioral;