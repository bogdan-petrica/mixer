-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.math_real.all;

entity tb_gain_rom is
end tb_gain_rom;

architecture behavioral of tb_gain_rom is
    signal aclk : std_logic;
    signal rden : std_logic;
    
    signal a : std_logic_vector(6 downto 0);
    signal b : std_logic_vector(6 downto 0);
    signal c : std_logic_vector(6 downto 0);
    signal d : std_logic_vector(6 downto 0);
    
    signal da : std_logic_vector(15 downto 0);
    signal db : std_logic_vector(15 downto 0);
    signal dc : std_logic_vector(15 downto 0);
    signal dd : std_logic_vector(15 downto 0);
begin
    uut: entity work.gain_rom port map(
        aclk => aclk,
        rden => rden,
        
        a => a,
        b => b,
        c => c,
        d => d,
        
        da => da,
        db => db,
        dc => dc,
        dd => dd 
    );

    gen_clk: process
    begin
        aclk <= '0';
        wait for 5ns;
        aclk <= '1';
        wait for 5ns;
    end process gen_clk;
    
    stimulus: process
        variable decibell : real;
        variable int : real;
        variable rom_decibell : real;
        variable i : integer;
        
        variable sel : std_logic_vector(6 downto 0);
    begin
        rden <= '1';
        
        for i in 0 to 46 loop
            a <= std_logic_vector(to_unsigned(i, 7));
            wait until rising_edge(aclk);
            wait until rising_edge(aclk);
            
            assert da = X"0000" report "rom gain not valid" severity FAILURE;
        end loop;
        
        for i in 0 to 79 loop
            decibell := -34.0 + real(i) * 0.5;
            sel := std_logic_vector(to_unsigned(47 + i, 7));
            
            a <= sel;
            b <= sel;
            c <= sel;
            d <= sel;
            
            wait until rising_edge(aclk);
            wait until rising_edge(aclk);
            
            int := real(to_integer(signed(da))) / 8192;
            
            rom_decibell := 10 * log10(int); 
            
            assert abs(decibell - rom_decibell) < 0.5 report "rom gain not valid" severity FAILURE;
            
            assert da = db report "rom port b not valid" severity FAILURE;
            assert da = dc report "rom port c not valid" severity FAILURE;
            assert da = dd report "rom port d not valid" severity FAILURE;
        end loop;
        
        a <= std_logic_vector(to_unsigned(65, 7));
        b <= std_logic_vector(to_unsigned(70, 7));
        c <= std_logic_vector(to_unsigned(79, 7));
        d <= std_logic_vector(to_unsigned(100, 7));
        wait until rising_edge(aclk);
        wait until rising_edge(aclk);
        
        assert (da < db) and (db < dc) and (dc < dd) report "rom ports not independent" severity FAILURE;
        
        assert false report "success" severity NOTE;
        
        wait for 100ms;
    end process;
end behavioral;
