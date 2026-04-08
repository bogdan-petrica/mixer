-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity i2s_slave_rx is
    port(
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal bclk_rising_stb : in std_logic;
        signal word_stb : in std_logic;
        
        signal rx_data : out std_logic_vector(63 downto 0);
        
        signal pbdat : in std_logic
    );
end i2s_slave_rx;

architecture behavioral of i2s_slave_rx is
    signal rx_data_q : std_logic_vector(63 downto 0);
begin
    process(mclk, mresetn)
    begin
        if mresetn = '0' then
            rx_data_q <= (others => '0');
        elsif rising_edge(mclk) then
            if word_stb = '1' then
                rx_data_q <= (others => '0');
            elsif bclk_rising_stb = '1' then
                rx_data_q <= rx_data_q(62 downto 0) & pbdat;
            end if;
        end if;
    end process;
    
    rx_data <= rx_data_q;
end behavioral;
