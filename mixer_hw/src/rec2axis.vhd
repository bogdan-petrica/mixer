-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity rec2axis is
    port(
        signal aclk : in std_logic;
        signal aresetn : in std_logic;
    
        -- master AXIS
        signal m_axis_tdata : out std_logic_vector(31 downto 0);
        signal m_axis_tid : out std_logic_vector(2 downto 0);
        signal m_axis_tkeep : out std_logic_vector(3 downto 0);
        signal m_axis_tlast : out std_logic;
        signal m_axis_tready : in std_logic;
        signal m_axis_tvalid : out std_logic;
        
        -- fifo
        signal fifo_rst : in std_logic;
        signal fifo_ardy : in std_logic;
        signal fifo_mrdy : in std_logic;
        
        -- ctrl
        signal rec_act : in std_logic;
        signal rec_size : in std_logic_vector(15 downto 0);
        signal rec_en : in std_logic;
        
        signal rec_done : out std_logic;
        signal rec_en_status : out std_logic;
        
        signal rec_full_cnt : out std_logic_vector(15 downto 0);
        
        -- rec
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal sstb : in std_logic; 
        signal left : in std_logic_vector(23 downto 0);
        signal right : in std_logic_vector(23 downto 0)
    );

end rec2axis;

architecture behavioral of rec2axis is
    attribute async_reg : string;

    signal di : std_logic_vector(31 downto 0);
    signal dip : std_logic_vector(3 downto 0);
    signal wren : std_logic;
    signal rden : std_logic;
    signal rst : std_logic;
    signal do : std_logic_vector(31 downto 0);
    signal dop : std_logic_vector(3 downto 0);
    signal full : std_logic;
    signal empty : std_logic;

    -- enque side, signal names are prefixed with enq_
    signal enq_en_ff : std_logic_vector(1 downto 0);
    attribute async_reg of enq_en_ff : signal is "true";
    signal enq_en : std_logic;
    
    signal enq_ready : std_logic;
    signal enq_full_cnt : unsigned(15 downto 0);
    
    -- deque side
    constant TxReset : std_logic_vector(2 downto 0) := "000";
    constant TxIdle : std_logic_vector(2 downto 0) := "001";
    constant TxReady : std_logic_vector(2 downto 0) := "010";
    constant TxRun : std_logic_vector(2 downto 0) := "011";
    constant TxDone : std_logic_vector(2 downto 0) := "100";
    constant TxDrain : std_logic_vector(2 downto 0) := "101";
    
    signal en_status_ff : std_logic_vector(1 downto 0);
    attribute async_reg of en_status_ff : signal is "true";
    signal en_status : std_logic;

    signal tx_cnt : unsigned(15 downto 0);
    signal state : std_logic_vector(2 downto 0);
    signal last : std_logic;
    signal drain_cnt : unsigned(15 downto 0);
    
    signal full_cnt_0 : unsigned(15 downto 0);
    attribute async_reg of full_cnt_0 : signal is "true";

    signal full_cnt_1 : unsigned(15 downto 0);
    attribute async_reg of full_cnt_1 : signal is "true";
    
begin
    rst <= fifo_rst;
    
    enq_en_ff_gen: process(mclk, mresetn)
    begin
        if mresetn = '0' then
            enq_en_ff <= (others => '0');
        elsif rising_edge(mclk) then
            enq_en_ff <= enq_en_ff(0) & rec_en;
        end if;
    end process enq_en_ff_gen;
    
    enq_en <= enq_en_ff(1);
    enq_ready <= fifo_mrdy and enq_en;
    
    enq_gen: process(mclk, mresetn)
    begin
        if mresetn = '0' then
            enq_full_cnt <= (others => '0');
        elsif rising_edge(mclk) then
            if enq_ready = '1' then
                if (full = '1') and (sstb = '1') then
                    enq_full_cnt <= enq_full_cnt + 1;
                end if;
            end if;
        end if;
    end process enq_gen;
    
    -- fifo write enable out
    wren <= '1' when (enq_ready = '1') and (full = '0') and (sstb = '1') else '0';
    
    -- fifo data input out
    di <= left(23 downto 8) & right(23 downto 8);
    
    en_status_ff_gen: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            en_status_ff <= (others => '0');
        elsif rising_edge(aclk) then
            en_status_ff <= en_status_ff(0) & enq_en;
        end if;
    end process en_status_ff_gen;
    
    en_status <= en_status_ff(1);
    
    tx_gen: process (aclk, aresetn)
    begin
        if aresetn = '0' then
            tx_cnt <= (others => '0');
            state <= TxReset;
            drain_cnt <= (others => '0');
        elsif rising_edge(aclk) then
            if state = TxReset then
                if fifo_ardy = '1' then
                    state <= TxIdle;
                end if;
            elsif state = TxIdle then
                if en_status = '1' then
                    state <= TxReady;
                end if;
            elsif state = TxReady then
                if en_status = '0' then
                    if empty = '0' then
                        state <= TxDrain;
                    else
                        state <= TxIdle;
                    end if;
                elsif rec_act = '1' then
                    if unsigned(rec_size) = 0 then
                        state <= TxDone;
                    else
                        tx_cnt <= unsigned(rec_size);
                        state <= TxRun;
                    end if;
                end if;
            elsif state = TxRun then
                if empty = '0' and m_axis_tready = '1' then
                    if last = '1' then
                        state <= TxDone;
                    end if;

                    tx_cnt <= tx_cnt - 1;
                end if;
            elsif state = TxDone then
                if rec_act = '0' then
                    state <= TxReady;
                end if;
            elsif state = TxDrain then
                if en_status = '1' then
                    state <= TxReady;
                else
                    if empty = '1' then
                        state <= TxIdle;
                    else
                        drain_cnt <= drain_cnt + 1;
                    end if;
                end if;
            else
                state <= state;
            end if;
        end if;
    end process tx_gen;
    
    last <= '1' when tx_cnt = X"0001" else '0';
    
    -- master axis stream out signals
    m_axis_tdata <= do;
    m_axis_tid <= (others => '0');
    m_axis_tkeep <= "1111";
    m_axis_tlast <= last;
    m_axis_tvalid <= '1' when (state = TxRun) and (empty = '0') else '0'; 
    rden <= '1' when (((state = TxRun) and (empty = '0') and (m_axis_tready = '1')) or ((state = TxDrain) and (empty = '0'))) else '0';
    
    -- rec_done out
    rec_done <= '1' when state = TxDone else '0';
    
    -- rec_en_status out
    rec_en_status <= '0' when (state = TxReset) or (state = TxIdle) else '1';
    
    -- synchornize enq_full_cnt to aclk domain
    full_cnt_gen: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            full_cnt_0 <= (others => '0');
            full_cnt_1 <= (others => '0');
        elsif rising_edge(aclk) then
            full_cnt_0 <= enq_full_cnt;
            full_cnt_1 <= full_cnt_0;
        end if;
    end process full_cnt_gen;
    
    -- rec_full_cnt out
    rec_full_cnt <= std_logic_vector(full_cnt_1);
    
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
            wrclk => mclk,
            rden => rden,
            rdclk => aclk,
            rst => rst,
            do => do,
            dop => dop,
            full => full,
            empty => empty,
            regce => '1',
            rstreg => '0');

end behavioral;
