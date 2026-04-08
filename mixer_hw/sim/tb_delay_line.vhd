-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.math_real.all;

entity tb_delay_line is
end tb_delay_line;

architecture behavioral of tb_delay_line is
    constant DELAY_SIZE : integer := 16384;

    signal mclk : std_logic;
    signal mresetn : std_logic;
    
    signal delay : std_logic_vector(15 downto 0);
    
    signal stb : std_logic;
    signal di : std_logic_vector(31 downto 0);
    signal do : std_logic_vector(31 downto 0);
    
    function get_next_sample(sample : std_logic_vector) return std_logic_vector is
        variable result : std_logic_vector(sample'high downto sample'low);
        variable i : integer;
    begin
        for i in sample'high / 8 downto sample'low / 8 loop
            result(8*i + 7 downto 8*i) := std_logic_vector(unsigned(sample(8*i + 7 downto 8*i)) + 1);
        end loop;
        
        return result;
    end function get_next_sample;
    
    type SAMPLE_ARR is array(0 to DELAY_SIZE - 1) of std_logic_vector(31 downto 0);
    
    type DELAY_TEST_VECTOR is record
        delay : integer;
        hold_count : integer;
    end record;
    
    type DELAY_TEST_VECTOR_ARR is array(natural range <>) of DELAY_TEST_VECTOR;
    
    constant delay_test_vectors :  DELAY_TEST_VECTOR_ARR := 
        (
            (1000,      2000),
            (200,       4000),
            (13000,    12000),
            (0,          300),
            (5000,     21000),
            (20000,      500)); 
            
    function get_delay_total_count(delay_test_vectors : DELAY_TEST_VECTOR_ARR) return integer is
        variable i : integer;
        variable result : integer := 0;
    begin
        for i in 0 to delay_test_vectors'length - 1 loop
            result := result + delay_test_vectors(i).hold_count;
        end loop;
        return result;
    end function get_delay_total_count;
    
    constant verify_sample_count : integer := get_delay_total_count(delay_test_vectors); 
begin
    uut: entity work.delay_line port map (
        mclk => mclk,
        mresetn => mresetn,
        
        delay => delay,
        
        stb => stb,
        di => di,
        do => do
    );
    
    mclk_gen: process
    begin
        mclk <= '0';
        wait for 40.69ns;
        mclk <= '1';
        wait for 40.69ns;
    end process mclk_gen;
    
    verify: process
        variable samples : SAMPLE_ARR := (others => (others => '0')); 
        variable wa : integer := 0;
        variable ra : integer;
        variable sample_count : integer := 0;
        variable expected : std_logic_vector(31 downto 0) := (others => '0');
    begin
        wait until rising_edge(mclk) and mresetn = '1';
        
        assert do = expected report "invalid read value" severity FAILURE;
        
        if stb = '1' then
            ra := (wa  - 1 - to_integer(unsigned(delay))) mod DELAY_SIZE;
            expected := samples(ra);
        
            samples(wa) := di;
            wa := (wa + 1) mod DELAY_SIZE;
            
            sample_count := sample_count + 1;
        end if;
        
        if sample_count > verify_sample_count then
            assert false report "success" severity NOTE;
            wait;
        end if;
    end process verify;
    
    stimulus_delay: process
        variable i, j : integer;
    begin
        wait until rising_edge(mclk) and mresetn = '1';
        for i in 0 to delay_test_vectors'length - 1 loop
            delay <= std_logic_vector(to_unsigned(delay_test_vectors(i).delay, 16));
            
            for j in 0 to  delay_test_vectors(i).hold_count - 1 loop
                wait until rising_edge(mclk) and stb = '1';
            end loop;
        end loop;
        
        wait;
    end process stimulus_delay;
    
    stimulus_reset: process
    begin
        mresetn <= '0';
        
        for i in 0 to 7 loop
            wait until rising_edge(mclk);
        end loop;
        
        mresetn <= '1';
        wait until rising_edge(mclk); 
        
        wait;
    end process stimulus_reset;
    
    stimulus_sample: process
        variable i, j, k : integer;
        
        variable seed1 : integer := 1;
        variable seed2 : integer := 1;
        
        variable rand : real;
        variable noop_count : integer;
        
        variable sample : std_logic_vector(31 downto 0) := X"01234567";
    begin
        wait until rising_edge(mclk) and mresetn = '1';

        stb <= '0';
        wait until rising_edge(mclk);
        
        loop
            stb <= '1';
            di <= sample;
            sample := get_next_sample(sample);
            wait until rising_edge(mclk);
            
            uniform(seed1, seed2, rand);
            noop_count := integer(floor(rand * 4.0));
            
            for k in 1 to noop_count - 1 loop
                stb <= '0';
                wait until rising_edge(mclk);
            end loop;
        end loop;
    end process stimulus_sample;
end behavioral;
