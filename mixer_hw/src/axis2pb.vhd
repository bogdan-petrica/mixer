-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity axis2pb is
    port (
        signal aclk : in std_logic;
        signal aresetn : in std_logic;
        
        -- slave AXIS
        signal s_axis_tdata : in std_logic_vector(31 downto 0);
        signal s_axis_tid : in std_logic_vector(2 downto 0);
        signal s_axis_tkeep : in std_logic_vector(3 downto 0);
        signal s_axis_tlast : in std_logic;
        signal s_axis_tready : out std_logic;
        signal s_axis_tvalid : in std_logic;
        
        -- fifo
        signal fifo_rst : in std_logic;
        signal fifo_ardy : in std_logic;
        signal fifo_mrdy : in std_logic;
        
        -- pb
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal sstb : in std_logic;
        signal left : out std_logic_vector(23 downto 0);
        signal right : out std_logic_vector(23 downto 0)
    );
end axis2pb;

architecture behavioral of axis2pb is

    signal di : std_logic_vector(31 downto 0);
    signal dip : std_logic_vector(3 downto 0);
    signal wren : std_logic;
    signal rden : std_logic;
    signal rst : std_logic;
    signal do : std_logic_vector(31 downto 0);
    signal dop : std_logic_vector(3 downto 0);
    signal full : std_logic;
    signal empty : std_logic;
    
    signal enq_rdy : std_logic; 
    
    signal deq_valid : std_logic;

begin
    rst <= fifo_rst;
    
    enq_rdy <= '1' when (fifo_ardy = '1') and (full = '0') else '0';
    s_axis_tready <= enq_rdy;
    
    di <= s_axis_tdata;
    wren <= '1' when (enq_rdy = '1') and (s_axis_tvalid = '1') else '0';
    
    deq_valid <= '1' when (fifo_mrdy = '1') and (empty = '0') else '0';
       
    left <= (do(31 downto 16) & X"00") when (deq_valid = '1') else (others => '0');
    right <= (do(15 downto 0) & X"00") when (deq_valid = '1') else (others => '0');
    
    rden <= '1' when (deq_valid = '1') and (sstb = '1') else '0';

    fifo : FIFO18E1
        generic map (
            first_word_fall_through => true,
            do_reg => 1,
            data_width => 36,
            fifo_mode => "FIFO18_36",
            en_syn => false,
            sim_device => "7SERIES")
        port map (
            di => di,
            dip => dip,
            wren => wren,
            wrclk => aclk,
            rden => rden,
            rdclk => mclk,
            rst => rst,
            do => do,
            dop => dop,
            full => full,
            empty => empty,
            regce => '1',
            rstreg => '0');
end behavioral;
