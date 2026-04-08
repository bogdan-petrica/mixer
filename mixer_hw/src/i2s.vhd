-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity i2s is
    port (
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        -- audio codec i2s interface
        signal bclk : out std_logic;
        
        signal pblrc : out std_logic;
        signal pbdat : out std_logic; 
        
        signal reclrc : out std_logic;
        signal recdat : in std_logic;
        
        signal muten : out std_logic;
        
        -- rec interface
        signal rec_data : out std_logic_vector(63 downto 0);
        signal rec_sstb  : out std_logic;
        
        -- pb interface
        signal pb_data : in std_logic_vector(63 downto 0);
        signal pb_sstb : out std_logic
    );
end i2s;

architecture behavioral of i2s is
    signal cnt : unsigned(7 downto 0);
    
    signal recdatc : std_logic; 
    signal recdatq : std_logic_vector(63 downto 0);
    
    signal pbdatc : std_logic;
    signal pbdatq : std_logic_vector(63 downto 0);
    
    -- dec from decoder
    signal pbsstb_dec : std_logic; 
begin
    cnt_gen: process(mclk, mresetn)
    begin
        if mresetn = '0' then
            cnt <= (others => '0');
        elsif rising_edge(mclk) then
            cnt <= cnt + 1;
        end if;
    end process cnt_gen;
    
    bclk <= cnt(1);
    
    recdatc <= '1' when cnt(1 downto 0)= "01" else '0';
    reclrc <= cnt(7);
    
    rec_data <= recdatq;
    rec_sstb <= '1' when cnt = X"03" else '0';
    
    recdat_q_gen: process(mclk, mresetn)
    begin
        if mresetn = '0' then
            recdatq <= (others => '0');
        elsif rising_edge(mclk) then
            if recdatc = '1' then
                recdatq <= recdatq(62 downto 0) & recdat;
            end if;
        end if;
    end process recdat_q_gen;
    
    pbdatc <= '1' when cnt(1 downto 0) = "11" else '0';
    pblrc <= cnt(7);
    
    pbsstb_dec <= '1' when cnt = X"03" else '0';
    pb_sstb <= pbsstb_dec;
    
    pbdat_q_gen: process(mclk, mresetn)
    begin
        if mresetn = '0' then
            pbdatq <= (others => '0');
        elsif rising_edge(mclk) then
            if pbsstb_dec = '1' then
                pbdatq <= pb_data;
            elsif pbdatc = '1' then
                pbdatq <= pbdatq(62 downto 0) & "0";
            end if;
        end if;
    end process pbdat_q_gen;
    
    pbdat <= pbdatq(63);
    
    muten <= '1';
    
end behavioral;
