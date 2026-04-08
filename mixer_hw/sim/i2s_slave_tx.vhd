-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity i2s_slave_tx is
    port (
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal bclk_falling_stb : in std_logic;
        signal word_stb : in std_logic;
        
        signal tx_data : in std_logic_vector(63 downto 0);
        
        signal recdat : out std_logic
    );
end i2s_slave_tx;

architecture behavioral of i2s_slave_tx is
    signal tx_data_q : std_logic_vector(63 downto 0);
begin
    process(mclk, mresetn)
    begin
        if mresetn = '0' then
            tx_data_q <= (others => '0');
        elsif rising_edge(mclk) then
            if word_stb = '1' then
                tx_data_q <= tx_data;
            elsif bclk_falling_stb = '1' then
                tx_data_q <= tx_data_q(62 downto 0) & "0";
            end if;
        end if;
    end process;
    
    recdat <= tx_data_q(63);
end behavioral;
