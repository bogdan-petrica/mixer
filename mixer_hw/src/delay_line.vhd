-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.math_real.all;

entity delay_line is
    port (
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal delay : in std_logic_vector(15 downto 0);

        signal stb : in std_logic;        
        signal di : in std_logic_vector(31 downto 0);
        signal do : out std_logic_vector(31 downto 0)
    ); 
end delay_line;

architecture behavioral of delay_line is
    -- 36Kb BRAM has 32Kb for data (4Kb for parity)
    -- each sample uses 32b => each BRAM can store 1024 samples, at 48000hz this means 0.0213 sec
    -- the 7z010 has 60 x 36Kb BRAM, up to 20 in a BRAM column
    -- start with 16 BRAM x 32Kb, at 48000hz this gives 0.3413 sec
    constant BRAM_COUNT : integer := 16;
    constant SIZE : integer := 1024 * BRAM_COUNT;
    
    constant WIDTH_REAL : real := log2(real(SIZE));
    constant WIDTH : integer := integer(WIDTH_REAL);
    
    type BRAM_TYPE is array(0 to SIZE - 1) of std_logic_vector(31 downto 0);
    
    signal bram : BRAM_TYPE := (others => (others => '0'));
    
    signal d : unsigned(WIDTH - 1 downto 0);
    signal wa : unsigned(WIDTH - 1 downto 0);
    signal ra : unsigned(WIDTH - 1 downto 0);
begin
    assert WIDTH_REAL = real(WIDTH) report "BRAM SIZE must be power of two" severity FAILURE;

    d <= unsigned(delay(WIDTH - 1 downto 0));
    ra <= wa - (d + 1);

    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                wa <= (others => '0');
            else
                if stb = '1' then
                    bram(to_integer(wa)) <= di;
                    wa <= wa + 1;
                end if;
            end if;
        end if;
    end process;
    
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                do <= (others => '0');
            else
                if stb = '1' then
                    do <= bram(to_integer(ra));
                end if;
            end if;
        end if;
    end process;
end behavioral;
