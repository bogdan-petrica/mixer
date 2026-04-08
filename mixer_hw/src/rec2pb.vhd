-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity rec2pb is
    port (
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal rec_data : in std_logic_vector(63 downto 0);
        signal rec_sstb : in std_logic;
        
        signal pb_data : out std_logic_vector(63 downto 0);
        signal pb_sstb : in std_logic
    );
end rec2pb;

architecture behavioral of rec2pb is
    signal data : std_logic_vector(63 downto 0);
begin
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                data <= (others => '0');
            else
                if rec_sstb = '1' then
                    data <= rec_data;
                elsif pb_sstb = '1' then
                    data <= (others => '0');
                end if;
            end if;
        end if;
    end process;
    
    pb_data <= data;
end behavioral;
