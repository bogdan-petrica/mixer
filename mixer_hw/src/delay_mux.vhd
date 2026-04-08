-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity delay_mux is
    port (
        signal sel : in std_logic_vector(1 downto 0);
        
        signal ramp_in : in std_logic_vector(63 downto 0);
        signal ps_in : in std_logic_vector(63 downto 0);
        signal mic_in : in std_logic_vector(63 downto 0);
        signal core_in : in std_logic_vector(63 downto 0);
        
        signal result : out std_logic_vector(63 downto 0)
    );
end delay_mux;

architecture behavioral of delay_mux is
    constant DELAY_RAMP_SEL : std_logic_vector(1 downto 0) := "00";
    constant DELAY_PS_SEL : std_logic_vector(1 downto 0) := "01";
    constant DELAY_MIC_SEL : std_logic_vector(1 downto 0) := "10";
    constant DELAY_CORE_SEL : std_logic_vector(1 downto 0) := "11";
begin
    with sel select result <=
        ramp_in when DELAY_RAMP_SEL,
        ps_in when DELAY_PS_SEL,
        mic_in when DELAY_MIC_SEL,
        core_in when DELAY_CORE_SEL;
end behavioral;
