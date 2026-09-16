--///////////////////////////////////////////////////////////////////////////////
--//                                                                           //
--//    Copyright © 2016  Angel Francisco Jimenez-Fernandez                    //
--//                                                                           //
--//    This file is part of OpenNAS.                                          //
--//                                                                           //
--//    OpenNAS is free software: you can redistribute it and/or modify        //
--//    it under the terms of the GNU General Public License as published by   //
--//    the Free Software Foundation, either version 3 of the License, or      //
--//    (at your option) any later version.                                    //
--//                                                                           //
--//    OpenNAS is distributed in the hope that it will be useful,             //
--//    but WITHOUT ANY WARRANTY; without even the implied warranty of         //
--//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the            //
--//    GNU General Public License for more details.                           //
--//                                                                           //
--//    You should have received a copy of the GNU General Public License      //
--//    along with OpenNAS. If not, see <http://www.gnu.org/licenses/>.        //
--//                                                                           //
--///////////////////////////////////////////////////////////////////////////////


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity PFBank_32CH is
    Port (
        clock      : in  STD_LOGIC;
        rst        : in  STD_LOGIC;
        spikes_in  : in  STD_LOGIC_VECTOR(1 downto 0);
        spikes_out : out STD_LOGIC_VECTOR(63 downto 0)
    );
end PFBank_32CH;

architecture PFBank_arq of PFBank_32CH is

    component spikes_BPF_HQ is
        Generic (
            GL             : INTEGER := 11;
            SAT            : INTEGER := 1023
        );
        Port (
            CLK            : in  STD_LOGIC;
            RST            : in  STD_LOGIC;
            FREQ_DIV       : in  STD_LOGIC_VECTOR(7 downto 0);
            SPIKES_DIV     : in  STD_LOGIC_VECTOR(15 downto 0);
            SPIKES_DIV_FB  : in  STD_LOGIC_VECTOR(15 downto 0);
            SPIKES_DIV_OUT : in  STD_LOGIC_VECTOR(15 downto 0);
            spike_in_p     : in  STD_LOGIC;
            spike_in_n     : in  STD_LOGIC;
            spike_out_p    : out STD_LOGIC;
            spike_out_n    : out STD_LOGIC
        );
    end component;

    signal not_rst: std_logic;

    begin

        not_rst <= not rst;

        --Ideal cutoff: 22000.0000Hz - Real cutoff: 21998.6733Hz - Error: 0.0060%
        U_BPF_0: spikes_BPF_HQ
        Generic Map (
            GL             => 8,
            SAT            => 127
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"5E5C",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(1),
            spike_out_n    => spikes_out(0) 
        );

        --Ideal cutoff: 17551.4596Hz - Real cutoff: 17550.2470Hz - Error: 0.0069%
        U_BPF_1: spikes_BPF_HQ
        Generic Map (
            GL             => 8,
            SAT            => 127
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"70EB",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(3),
            spike_out_n    => spikes_out(2) 
        );

        --Ideal cutoff: 14002.4425Hz - Real cutoff: 14001.8878Hz - Error: 0.0040%
        U_BPF_2: spikes_BPF_HQ
        Generic Map (
            GL             => 9,
            SAT            => 255
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"781E",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(5),
            spike_out_n    => spikes_out(4) 
        );

        --Ideal cutoff: 11171.0593Hz - Real cutoff: 11170.5467Hz - Error: 0.0046%
        U_BPF_3: spikes_BPF_HQ
        Generic Map (
            GL             => 9,
            SAT            => 255
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"5FD4",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(7),
            spike_out_n    => spikes_out(6) 
        );

        --Ideal cutoff: 8912.1998Hz - Real cutoff: 8911.7273Hz - Error: 0.0053%
        U_BPF_4: spikes_BPF_HQ
        Generic Map (
            GL             => 9,
            SAT            => 255
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"72AD",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(9),
            spike_out_n    => spikes_out(8) 
        );

        --Ideal cutoff: 7110.0961Hz - Real cutoff: 7109.7716Hz - Error: 0.0046%
        U_BPF_5: spikes_BPF_HQ
        Generic Map (
            GL             => 10,
            SAT            => 511
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"79FC",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(11),
            spike_out_n    => spikes_out(10) 
        );

        --Ideal cutoff: 5672.3893Hz - Real cutoff: 5672.0168Hz - Error: 0.0066%
        U_BPF_6: spikes_BPF_HQ
        Generic Map (
            GL             => 10,
            SAT            => 511
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"6151",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(13),
            spike_out_n    => spikes_out(12) 
        );

        --Ideal cutoff: 4525.3960Hz - Real cutoff: 4525.2280Hz - Error: 0.0037%
        U_BPF_7: spikes_BPF_HQ
        Generic Map (
            GL             => 10,
            SAT            => 511
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"7476",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(15),
            spike_out_n    => spikes_out(14) 
        );

        --Ideal cutoff: 3610.3321Hz - Real cutoff: 3610.2103Hz - Error: 0.0034%
        U_BPF_8: spikes_BPF_HQ
        Generic Map (
            GL             => 11,
            SAT            => 1023
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"7BE2",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(17),
            spike_out_n    => spikes_out(16) 
        );

        --Ideal cutoff: 2880.2999Hz - Real cutoff: 2880.1769Hz - Error: 0.0043%
        U_BPF_9: spikes_BPF_HQ
        Generic Map (
            GL             => 11,
            SAT            => 1023
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"62D5",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(19),
            spike_out_n    => spikes_out(18) 
        );

        --Ideal cutoff: 2297.8849Hz - Real cutoff: 2297.7515Hz - Error: 0.0058%
        U_BPF_10: spikes_BPF_HQ
        Generic Map (
            GL             => 11,
            SAT            => 1023
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"7645",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(21),
            spike_out_n    => spikes_out(20) 
        );

        --Ideal cutoff: 1833.2379Hz - Real cutoff: 1833.1659Hz - Error: 0.0039%
        U_BPF_11: spikes_BPF_HQ
        Generic Map (
            GL             => 12,
            SAT            => 2047
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"7DCF",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(23),
            spike_out_n    => spikes_out(22) 
        );

        --Ideal cutoff: 1462.5455Hz - Real cutoff: 1462.4573Hz - Error: 0.0060%
        U_BPF_12: spikes_BPF_HQ
        Generic Map (
            GL             => 12,
            SAT            => 2047
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"645E",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(25),
            spike_out_n    => spikes_out(24) 
        );

        --Ideal cutoff: 1166.8095Hz - Real cutoff: 1166.7481Hz - Error: 0.0053%
        U_BPF_13: spikes_BPF_HQ
        Generic Map (
            GL             => 12,
            SAT            => 2047
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"781C",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(27),
            spike_out_n    => spikes_out(26) 
        );

        --Ideal cutoff: 930.8731Hz - Real cutoff: 930.8409Hz - Error: 0.0035%
        U_BPF_14: spikes_BPF_HQ
        Generic Map (
            GL             => 13,
            SAT            => 4095
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"7FC4",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(29),
            spike_out_n    => spikes_out(28) 
        );

        --Ideal cutoff: 742.6447Hz - Real cutoff: 742.6123Hz - Error: 0.0044%
        U_BPF_15: spikes_BPF_HQ
        Generic Map (
            GL             => 13,
            SAT            => 4095
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"65EE",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(31),
            spike_out_n    => spikes_out(30) 
        );

        --Ideal cutoff: 592.4772Hz - Real cutoff: 592.4430Hz - Error: 0.0058%
        U_BPF_16: spikes_BPF_HQ
        Generic Map (
            GL             => 13,
            SAT            => 4095
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"79FA",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(33),
            spike_out_n    => spikes_out(32) 
        );

        --Ideal cutoff: 472.6745Hz - Real cutoff: 472.6491Hz - Error: 0.0054%
        U_BPF_17: spikes_BPF_HQ
        Generic Map (
            GL             => 13,
            SAT            => 4095
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"6150",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(35),
            spike_out_n    => spikes_out(34) 
        );

        --Ideal cutoff: 377.0967Hz - Real cutoff: 377.0691Hz - Error: 0.0073%
        U_BPF_18: spikes_BPF_HQ
        Generic Map (
            GL             => 14,
            SAT            => 8191
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"6783",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(37),
            spike_out_n    => spikes_out(36) 
        );

        --Ideal cutoff: 300.8453Hz - Real cutoff: 300.8319Hz - Error: 0.0045%
        U_BPF_19: spikes_BPF_HQ
        Generic Map (
            GL             => 14,
            SAT            => 8191
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"7BE0",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(39),
            spike_out_n    => spikes_out(38) 
        );

        --Ideal cutoff: 240.0125Hz - Real cutoff: 239.9958Hz - Error: 0.0070%
        U_BPF_20: spikes_BPF_HQ
        Generic Map (
            GL             => 14,
            SAT            => 8191
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"62D3",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(41),
            spike_out_n    => spikes_out(40) 
        );

        --Ideal cutoff: 191.4804Hz - Real cutoff: 191.4730Hz - Error: 0.0039%
        U_BPF_21: spikes_BPF_HQ
        Generic Map (
            GL             => 15,
            SAT            => 16383
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"6920",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(43),
            spike_out_n    => spikes_out(42) 
        );

        --Ideal cutoff: 152.7619Hz - Real cutoff: 152.7543Hz - Error: 0.0049%
        U_BPF_22: spikes_BPF_HQ
        Generic Map (
            GL             => 15,
            SAT            => 16383
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"7DCD",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(45),
            spike_out_n    => spikes_out(44) 
        );

        --Ideal cutoff: 121.8724Hz - Real cutoff: 121.8667Hz - Error: 0.0047%
        U_BPF_23: spikes_BPF_HQ
        Generic Map (
            GL             => 15,
            SAT            => 16383
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"645D",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(47),
            spike_out_n    => spikes_out(46) 
        );

        --Ideal cutoff: 97.2291Hz - Real cutoff: 97.2235Hz - Error: 0.0057%
        U_BPF_24: spikes_BPF_HQ
        Generic Map (
            GL             => 16,
            SAT            => 32767
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"6AC2",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(49),
            spike_out_n    => spikes_out(48) 
        );

        --Ideal cutoff: 77.5687Hz - Real cutoff: 77.5653Hz - Error: 0.0044%
        U_BPF_25: spikes_BPF_HQ
        Generic Map (
            GL             => 16,
            SAT            => 32767
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"7FC2",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(51),
            spike_out_n    => spikes_out(50) 
        );

        --Ideal cutoff: 61.8838Hz - Real cutoff: 61.8796Hz - Error: 0.0068%
        U_BPF_26: spikes_BPF_HQ
        Generic Map (
            GL             => 16,
            SAT            => 32767
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"65EC",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(53),
            spike_out_n    => spikes_out(52) 
        );

        --Ideal cutoff: 49.3705Hz - Real cutoff: 49.3677Hz - Error: 0.0058%
        U_BPF_27: spikes_BPF_HQ
        Generic Map (
            GL             => 17,
            SAT            => 65535
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"6C6B",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(55),
            spike_out_n    => spikes_out(54) 
        );

        --Ideal cutoff: 39.3875Hz - Real cutoff: 39.3856Hz - Error: 0.0047%
        U_BPF_28: spikes_BPF_HQ
        Generic Map (
            GL             => 17,
            SAT            => 65535
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"567F",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(57),
            spike_out_n    => spikes_out(56) 
        );

        --Ideal cutoff: 31.4231Hz - Real cutoff: 31.4212Hz - Error: 0.0059%
        U_BPF_29: spikes_BPF_HQ
        Generic Map (
            GL             => 17,
            SAT            => 65535
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"02",
            SPIKES_DIV     => x"6782",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(59),
            spike_out_n    => spikes_out(58) 
        );

        --Ideal cutoff: 25.0691Hz - Real cutoff: 25.0680Hz - Error: 0.0044%
        U_BPF_30: spikes_BPF_HQ
        Generic Map (
            GL             => 18,
            SAT            => 131071
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"6E1B",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(61),
            spike_out_n    => spikes_out(60) 
        );

        --Ideal cutoff: 20.0000Hz - Real cutoff: 19.9988Hz - Error: 0.0062%
        U_BPF_31: spikes_BPF_HQ
        Generic Map (
            GL             => 18,
            SAT            => 131071
        )
        Port Map (
            CLK            => clock,
            RST            => not_rst,
            FREQ_DIV       => x"01",
            SPIKES_DIV     => x"57D7",
            SPIKES_DIV_FB  => x"7FFF",
            SPIKES_DIV_OUT => x"0336",
            spike_in_p     => spikes_in(1),
            spike_in_n     => spikes_in(0),
            spike_out_p    => spikes_out(63),
            spike_out_n    => spikes_out(62) 
        );

end PFBank_arq;
