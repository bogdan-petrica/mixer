-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity rst_ctrl is
    port (
        signal aclk : in std_logic;
        signal rstn : in std_logic;
        
        signal mclk : in std_logic;
        signal mlatched : in std_logic;
        
        signal aresetn : out std_logic;
        signal mresetn : out std_logic;
        
        signal fifo_rst : out std_logic;
        signal fifo_ardy : out std_logic;
        signal fifo_mrdy : out std_logic
    );   
end rst_ctrl;

architecture behavioral of rst_ctrl is
    attribute async_reg : string;
    
    constant ARESETN_CYCLES : unsigned(7 downto 0) := X"10";
    constant MRESETN_CYCLES : unsigned(7 downto 0) := X"04";
    
    signal aresetn_cnt : unsigned(7 downto 0);
    signal aresetn_int : std_logic;
    signal acnt : unsigned(1 downto 0);
    signal ardy : std_logic;
    signal fifo_rst_sync : std_logic_vector(1 downto 0);
    attribute async_reg of fifo_rst_sync : signal is "true";
    signal fifo_rst_check : std_logic;
    
    signal mresetn_cnt : unsigned(7 downto 0);
    signal mresetn_int : std_logic;
    signal mcnt : unsigned(3 downto 0);
    signal fifo_rst_s : std_logic;
    signal mrdy : std_logic;
    
begin
    process(aclk, rstn, mlatched)
    begin
        if rstn = '0' or mlatched = '0' then
            aresetn_cnt <= (others => '0');
        elsif rising_edge(aclk) then
            if aresetn_int = '0' then
                aresetn_cnt <= aresetn_cnt + 1;
            end if;
        end if;
    end process;
    
    aresetn_int <= '1' when aresetn_cnt = ARESETN_CYCLES else '0';
    aresetn <= aresetn_int;
    
    process(mclk, rstn, mlatched)
    begin
        if rstn = '0' or mlatched = '0' then
            mresetn_cnt <= (others => '0');
        elsif rising_edge(mclk) then
            if mresetn_int = '0' then
                mresetn_cnt <= mresetn_cnt + 1;
            end if;
        end if;
    end process;
    
    mresetn_int <= '1' when mresetn_cnt = MRESETN_CYCLES else '0';
    mresetn <= mresetn_int;
    
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn_int = '0' then
                fifo_rst_sync <= "11";
            else
                fifo_rst_sync <= fifo_rst_sync(0) & fifo_rst_s;
            end if;
        end if;
    end process;
    
    fifo_rst_check <= fifo_rst_sync(1);
    
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn_int = '0' then
                acnt <= (others => '0');
            elsif fifo_rst_check = '0' then
                if ardy = '0' then
                    acnt <= acnt + 1;
                end if;
            end if;
        end if;
    end process;
    
    ardy <= '0' when acnt < "10" else '1';
    fifo_ardy <= ardy;
    
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn_int = '0' then
                mcnt <= (others => '0');
            elsif mrdy = '0' then
                mcnt <= mcnt + 1;
            end if;
        end if;
    end process;
    
    fifo_rst_s <= '1' when mcnt < "101" else '0';
    fifo_rst <= fifo_rst_s;
    
    mrdy <= '1' when mcnt = "111" else '0';
    fifo_mrdy <= mrdy;
end behavioral;
