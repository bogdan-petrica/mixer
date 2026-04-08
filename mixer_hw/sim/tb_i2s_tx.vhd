library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
--library UNISIM;
--use UNISIM.VComponents.all;

entity tb_i2s_tx is
end tb_i2s_tx;

architecture behavioral of tb_i2s_tx is
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
    signal pblrc_sync : std_logic;
    signal pb_sstb_sync : std_logic;
    signal cnt : unsigned(7 downto 0);
    
    signal bclk_rising_stb : std_logic;
    signal bclk_falling_stb : std_logic;
    signal word_stb : std_logic;
    
    signal prev_pb_data : std_logic_vector(63 downto 0);
    signal have_prev_pb_data : std_logic;
    
    signal rx_data : std_logic_vector(63 downto 0);
    signal rx_data_bitmap : std_logic_vector(63 downto 0);
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
        lrc => pblrc,
        stb => pb_sstb,
        
        fail => fail,
        sync => sync,
        bclk_sync => bclk_sync,
        lrc_sync => pblrc_sync,
        stb_sync => pb_sstb_sync,
        cnt => cnt,
        
        bclk_rising_stb => bclk_rising_stb,
        bclk_falling_stb => bclk_falling_stb,
        word_stb => word_stb
    );
    
    inst_i2s_slave_rx: entity work.i2s_slave_rx port map(
        mclk => mclk,
        mresetn => mresetn,
        
        bclk_rising_stb => bclk_rising_stb,
        word_stb => word_stb,
        
        rx_data => rx_data,
        
        pbdat => pbdat
    );
    
    verify_data: process(mclk, mresetn)
    begin
        if mresetn = '0' then
            pb_data <= (others => '0');
            prev_pb_data <= (others => '0');
            have_prev_pb_data <= '0';
            
            rx_data_bitmap <= (others => '0');
        elsif rising_edge(mclk) then
            if sync = '1' then
                if word_stb = '1' then
                    if have_prev_pb_data = '1' then
                        assert rx_data = prev_pb_data report "invalid rx_data" severity FAILURE;
                        rx_data_bitmap <= rx_data_bitmap or rx_data;
                    end if;
                end if;
            
                if pb_sstb = '1' then
                    pb_data <= std_logic_vector(unsigned(pb_data) + X"010101_01_010101_01");
                    prev_pb_data <= pb_data;
                    have_prev_pb_data <= '1';
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
                assert pblrc_sync = '1' report "pblrc out of sync" severity FAILURE;
                assert pb_sstb_sync = '1' report "pb_sstb out of sync" severity FAILURE;
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
            exit when rx_data_bitmap = X"ffffffffffffffff";
        end loop;
        
        assert false report "success" severity NOTE;

        wait for 1000ms;
    end process stimulus;
end behavioral;
