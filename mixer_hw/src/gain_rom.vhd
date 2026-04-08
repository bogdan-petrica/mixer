-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

entity gain_rom is
    port(
        signal aclk : in std_logic;
        signal rden : in std_logic;
        
        signal a: in std_logic_vector(6 downto 0);
        signal b : in std_logic_vector(6 downto 0);
        signal c : in std_logic_vector(6 downto 0);
        signal d : in std_logic_vector(6 downto 0);
        
        signal da : out std_logic_vector(15 downto 0);
        signal db : out std_logic_vector(15 downto 0);
        signal dc : out std_logic_vector(15 downto 0);
        signal dd : out std_logic_vector(15 downto 0)
    );
end gain_rom;

architecture behavioral of gain_rom is
    type ROM_TYPE is array(0 to 127) of std_logic_vector(15 downto 0);
    
    impure function load_rom_from_file(file_path : string) return ROM_TYPE is
        variable i : integer;

        file table_file : text;
        variable file_line : line;
        variable data : bit_vector(15 downto 0);
        
        variable rom : ROM_TYPE; 
    begin
        file_open(table_file, file_path, READ_MODE);
        
        for i in 0 to 127 loop
            assert not endfile(table_file) report "file empty" severity FAILURE;
            readline(table_file, file_line);
            read(file_line, data);
            rom(i) := to_stdlogicvector(data);
        end loop;
        
        assert endfile(table_file) report "file not empty" severity FAILURE;
        return rom;
    end function load_rom_from_file;

    signal rom : ROM_TYPE := load_rom_from_file("gain_table.mem");
begin
    process(aclk)
    begin
        if rising_edge(aclk) then
            if rden = '1' then
                da <= rom(to_integer(unsigned(a)));
                db <= rom(to_integer(unsigned(b)));
                dc <= rom(to_integer(unsigned(c)));
                dd <= rom(to_integer(unsigned(d)));
            end if; 
        end if;
    end process;
end behavioral;

