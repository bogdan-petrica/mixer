-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- verify bclk, lrc, stb against mclk
--      * bclk every 4 mclks, half period is 2 mclks 
--      * lrc every 256 mclks, half period is 128 mclks
--      * lrc transitions on the falling edge of bclk
--          - ( 0_11111_1_1 -> 1_00000_0_0; 1_11111_1_1 -> 0_00000_0_0 ) 
--      * stb asserted on the bclk falling edge of the last sample
--          - cnt = X"03"
--
-- provides fail in case it can't synchronize within 256 mclks
--
-- provides bclk rising/falling stb and word stb( which is stb )

entity i2s_sync is
    port(
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal bclk : in std_logic;
        signal lrc : in std_logic;
        signal stb : in std_logic;
        
        signal fail : out std_logic;
        signal sync : out std_logic;
        signal bclk_sync : out std_logic;
        signal lrc_sync : out std_logic;
        signal stb_sync : out std_logic;
        signal cnt : out unsigned(7 downto 0);
        
        signal bclk_rising_stb : out std_logic;
        signal bclk_falling_stb : out std_logic;
        signal word_stb : out std_logic
    );
end i2s_sync;

architecture behavioral of i2s_sync is
    signal lrc_q : std_logic;
    signal fail_q : std_logic;
    signal sync_q : std_logic;
    signal sync_next : std_logic;
    
    signal cnt_q : unsigned(8 downto 0);
begin
    sync_check: process(mclk, mresetn)
    begin
        if mresetn = '0' then
            lrc_q <= '0';
            fail_q <= '0';
            sync_q <= '0';
            cnt_q <= (others => '0'); 
        elsif rising_edge(mclk) then
            if fail_q = '0' and sync_q = '0' then
                if lrc_q = '1' and lrc = '0' then
                    sync_q <= '1';
                    cnt_q <= "000000001";
                else
                    if cnt_q(8) = '1' then
                        fail_q <= '1';
                    end if;
                end if;
                lrc_q <= lrc;
            else
                cnt_q <= cnt_q + 1;
            end if;
        end if;
    end process sync_check;
    
    sync_next <= '1' when (fail_q = '0') and (sync_q = '0') and (lrc_q = '1') and (lrc = '0') else '0';
    
    fail <= fail_q;
    sync <= '1' when (sync_q = '1') or (sync_next = '1') else '0';
     
    bclk_sync <= '1' when (sync_q = '1') and (bclk = cnt_q(1)) else
                 '1' when (sync_next = '1') and (bclk = '0') else '0';
    
    lrc_sync <= '1' when (sync_q = '1') and (lrc = cnt_q(7)) else
                '1' when (sync_next = '1') and (lrc = '0') else '0';
                    
    stb_sync <= '1' when (sync_q = '1') and ((stb = '1') = (cnt_q(7 downto 0) = X"03")) else 
                '1' when (sync_next = '1') and (stb = '0') else '0';
    
    cnt <= cnt_q(7 downto 0);
    
    bclk_rising_stb <= '1' when cnt_q(1 downto 0) = "01" else '0';
    bclk_falling_stb <= '1' when cnt_q(1 downto 0) = "11" else '0';
    word_stb <= stb;
end behavioral;
