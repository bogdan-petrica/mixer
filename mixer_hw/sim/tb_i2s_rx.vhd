-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_i2s_rx is
end tb_i2s_rx;

architecture behavioral of tb_i2s_rx is
    signal mclk : std_logic;
    signal mresetn : std_logic;
        
    -- audio codec i2s interface
    signal bclk : std_logic;
    
    signal pblrc : std_logic;
    signal pbdat : std_logic; 
    
    signal reclrc : std_logic;
    signal recdat : std_logic;
    
    signal muten : std_logic;
    
    -- rec interface
    signal rec_data: std_logic_vector(63 downto 0);
    signal rec_sstb  : std_logic;
    
    -- pb interface
    signal pb_data : std_logic_vector(63 downto 0);
    signal pb_sstb : std_logic;
    
    signal fail : std_logic;
    signal sync : std_logic;
    signal bclk_sync : std_logic;
    signal reclrc_sync : std_logic;
    signal rec_sstb_sync : std_logic;
    signal cnt : unsigned(7 downto 0);
    
    signal bclk_rising_stb : std_logic;
    signal bclk_falling_stb : std_logic;
    signal word_stb : std_logic;
    
    signal tx_data : std_logic_vector(63 downto 0);
    signal prev_tx_data : std_logic_vector(63 downto 0);
    signal have_prev_tx_data : std_logic;
    
    signal rec_data_bitmap : std_logic_vector(63 downto 0);
begin
    uut: entity work.i2s port map (
        mclk => mclk,
        mresetn => mresetn,
        
        bclk => bclk,
        
        pblrc => pblrc,
        pbdat => pbdat,
        
        reclrc => reclrc,
        recdat => recdat,
        
        muten => muten,
        
        rec_data => rec_data,
        rec_sstb => rec_sstb,
        
        pb_data => pb_data,
        pb_sstb => pb_sstb
    );
    
    inst_i2s_sync: entity work.i2s_sync port map(
        mclk => mclk,
        mresetn => mresetn,
        
        bclk => bclk,
        lrc => reclrc,
        stb => rec_sstb,
        
        fail => fail,
        sync => sync,
        bclk_sync => bclk_sync,
        lrc_sync => reclrc_sync,
        stb_sync => rec_sstb_sync,
        cnt => cnt,
        
        bclk_rising_stb => bclk_rising_stb,
        bclk_falling_stb => bclk_falling_stb,
        word_stb => word_stb
    );
    
    inst_i2s_slave_tx: entity work.i2s_slave_tx port map(
        mclk => mclk,
        mresetn => mresetn,
        
        bclk_falling_stb => bclk_falling_stb,
        word_stb => word_stb,
        
        tx_data => tx_data,
        
        recdat => recdat
    );
    
    verify_data: process(mclk, mresetn)
    begin
        if mresetn = '0' then
            tx_data <= (others => '0');
            prev_tx_data <= (others => '0');
            have_prev_tx_data <= '0';
            rec_data_bitmap <= (others => '0');
        elsif rising_edge(mclk) then
            if sync = '1' then
                if rec_sstb = '1' then
                    if have_prev_tx_data = '1' then
                        assert rec_data = prev_tx_data report "invalid rec_data" severity FAILURE;
                        
                        rec_data_bitmap <= rec_data or rec_data_bitmap;
                    end if;
                end if; 
            
                if word_stb = '1' then
                    tx_data <= std_logic_vector(unsigned(tx_data) + X"010101_01_010101_01");
                    prev_tx_data <= tx_data;
                    have_prev_tx_data <= '1';
                end if;
            end if;
        end if;
    end process verify_data;
    
    verify_sync: process
    begin
        loop
            wait until rising_edge(mclk);
            
            assert fail = '0' report "failed to sync" severity FAILURE;
            
            if sync = '1' then
                assert bclk_sync = '1' report "bclk out of sync" severity FAILURE;
                assert reclrc_sync = '1' report "reclrc out of sync" severity FAILURE;
                assert rec_sstb_sync = '1' report "rec_sstb out of sync" severity FAILURE;
            end if;
        end loop;
    end process verify_sync;
        
    clk_gen: process
    begin
        mclk <= '0';
        wait for 40.69ns;
        mclk <= '1';
        wait for 40.69ns;
    end process clk_gen;
    
    stimulus: process
    begin
        mresetn <= '0';
        wait for 100ns;
        
        mresetn <= '1';
        wait until rising_edge(mclk);
        
        loop
            wait until rising_edge(mclk);
            exit when rec_data_bitmap = X"ffffffffffffffff";
        end loop;
        
        assert false report "success" severity NOTE;

        wait for 1000ms;
    end process stimulus;
end behavioral;
