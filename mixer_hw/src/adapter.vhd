-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library unisim;
use UNISIM.vcomponents.all;

entity adapter is
    port (
        signal scl_i : out std_logic;
        signal scl_o : in std_logic;
        signal scl_t : in std_logic;
        signal ac_scl : inout std_logic;
    
        signal sda_i : out std_logic;
        signal sda_o : in std_logic;
        signal sda_t : in std_logic;
        signal ac_sda : inout std_logic
    );
end adapter;

architecture behavioral of adapter is
begin
    IOBUF_scl : IOBUF
        generic map(
            DRIVE => 8,
            IOSTANDARD => "LVCMOS33",
            SLEW => "SLOW")
        port map(
            O => scl_i,
            I => scl_o,
            T => scl_t,
            IO => ac_scl);
     
    IOBUF_sda : IOBUF
        generic map(
            DRIVE => 8,
            IOSTANDARD => "LVCMOS33",
            SLEW => "SLOW")
        port map (
            O => sda_i,
            I => sda_o,
            T => sda_t,
            IO => ac_sda);    
end behavioral;
