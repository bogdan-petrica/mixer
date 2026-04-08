-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ramp_gen is
    port(
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal pb_data : out std_logic_vector(63 downto 0);
        signal pb_sstb : in std_logic
    );
end ramp_gen;

architecture behavioral of ramp_gen is
    -- FREQ(1/s) = 48KHZ / 2^7 = 375HZ
    -- T(s) = 2^7 / 48KHZ
    -- S = T(s) * FREQ(1/s) = 2^7 / 48KHZ * 48KHZ = 2^7
    -- 
    -- STEP = 2^24 / 2^7 = 2^17
    constant STEP : unsigned(23 downto 0) := to_unsigned(2**17, 24);

    signal cnt : unsigned(23 downto 0);
begin
    process(mclk, mresetn)
    begin
        if mresetn = '0' then
            cnt <= (others => '0');
        elsif rising_edge(mclk) then
            if pb_sstb = '1' then
                cnt <= cnt + step;
            end if;
        end if;
    end process;
    
    pb_data <= std_logic_vector(cnt) & X"00_000000_00";
end behavioral;
