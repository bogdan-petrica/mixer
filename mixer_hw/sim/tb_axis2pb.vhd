-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_axis2pb is
end tb_axis2pb;

architecture behavioral of tb_axis2pb is

    signal aclk : std_logic;
    signal rstn : std_logic;
    signal aresetn : std_logic;
    
    -- slave AXIS
    signal s_axis_tdata : std_logic_vector(31 downto 0);
    signal s_axis_tid : std_logic_vector(2 downto 0);
    signal s_axis_tkeep : std_logic_vector(3 downto 0);
    signal s_axis_tlast : std_logic;
    signal s_axis_tready : std_logic;
    signal s_axis_tvalid : std_logic;
    
    -- fifo
    signal fifo_rst : std_logic;
    signal fifo_ardy : std_logic;
    signal fifo_mrdy : std_logic;
    
    -- pb
    signal mclk : std_logic;
    signal mlatched : std_logic;
    signal mresetn : std_logic;
    
    signal sstb : std_logic; 
    signal left : std_logic_vector(23 downto 0);
    signal right : std_logic_vector(23 downto 0);
    
    procedure axis_tx(signal tvalid : out std_logic;
        signal tdata : out std_logic_vector(31 downto 0);
        signal tlast : out std_logic;
        data : inout unsigned(31 downto 0);
        current : inout integer;
        total : in integer) is
    begin
        assert current < total report "invalid call" severity FAILURE;
        
        tvalid <= '1';
        tdata <= std_logic_vector(data);
        
        if data(7 downto 0) = X"ff" then
            tlast <= '1';
        else
            tlast <= '0';
        end if;
        
        while current < total loop
            wait until rising_edge(aclk);
            if s_axis_tready = '1' then
                if data(7 downto 0) = X"ff" then
                    data := (data(31 downto 16) + X"0001") & X"0000";
                    tdata <= std_logic_vector(data);
                else
                    data := data + X"00000001";
                    tdata <= std_logic_vector(data);
                end if;
                
                
                if data(7 downto 0) = X"ff" then
                    tlast <= '1';
                else
                    tlast <= '0';
                end if;
                
                current := current + 1;
            end if;
        end loop;
        
        tvalid <= '0';
    end procedure axis_tx;
    
    procedure axis_tx_stall(signal tvalid : out std_logic;
        steps : in integer) is
        variable i : integer;
    begin
        assert steps > 0 report "invalid call" severity FAILURE;
        tvalid <= '0';

        for i in 0 to (steps - 1) loop
            wait until rising_edge(aclk);
        end loop;
    end procedure axis_tx_stall;
begin
    inst_rst_ctrl : entity work.rst_ctrl port map (
        aclk => aclk,
        rstn => rstn,
        mclk => mclk,
        mlatched => mlatched,
        aresetn => aresetn,
        mresetn => mresetn,
        fifo_rst => fifo_rst,
        fifo_ardy => fifo_ardy,
        fifo_mrdy => fifo_mrdy
    );
    
    uut : entity work.axis2pb port map (
        aclk => aclk,
        aresetn => aresetn,
        
        -- slave AXIS
        s_axis_tdata => s_axis_tdata,
        s_axis_tid => s_axis_tid,
        s_axis_tkeep => s_axis_tkeep,
        s_axis_tlast => s_axis_tlast,
        s_axis_tready => s_axis_tready,
        s_axis_tvalid => s_axis_tvalid,
        
        -- fifo
        fifo_rst => fifo_rst,
        fifo_ardy => fifo_ardy,
        fifo_mrdy => fifo_mrdy,
        
        -- pb
        mclk => mclk,
        mresetn => mresetn,
        
        sstb => sstb,
        left => left,
        right => right
    );
    
    aclk_gen: process
    begin
        aclk <= '0';
        wait for 5ns;
        aclk <= '1';
        wait for 5ns;
    end process aclk_gen;
    
    mclk_gen: process
    begin
        mclk <= '0';
        wait for 40.69ns;
        mclk <= '1';
        wait for 40.69ns;
    end process mclk_gen;
    
    sample_check: process
        variable prev_left : std_logic_vector(23 downto 0);
        variable prev_right : std_logic_vector(23 downto 0);
        
        variable i : integer;
    
    begin
        wait until rising_edge(mclk) and mresetn = '1';
        
        prev_left := X"000000";
        prev_right := X"00ff00";
        
        loop
            sstb <= '0';
            for i in 0 to 0 loop
                wait until rising_edge(mclk);
            end loop;
            
            sstb <= '1';
            wait until rising_edge(mclk);
            
            if left /= X"000000" then
                if prev_right = X"00ff00" then
                    assert left = std_logic_vector(unsigned(prev_left) + X"000100") report "invalid left" severity FAILURE;
                    assert right = X"000000" report "invalid right" severity FAILURE;
                else
                    assert left = prev_left report "invalid left" severity FAILURE;
                    assert right = std_logic_vector(unsigned(prev_right) + X"000100") report "invalid right" severity FAILURE;
                end if;
                
                prev_left := left;
                prev_right := right;
            else
                assert right = X"000000" report "invalid right" severity FAILURE;
            end if; 
        end loop;
    end process sample_check;
    
    stimulus: process
        variable data : unsigned(31 downto 0);
        variable current :  integer;
    begin
        -- aclk_freq / sstb_freq = 16.28 (see detailed calculations in tb_rec2_axis.vhd)
        rstn <= '0';
        mlatched <= '0';
        wait for 100ns;
        
        rstn <= '1';
        mlatched <= '1';
        wait for 100ns;
        
        wait until rising_edge(aclk) and aresetn = '1';
        
        data := X"00010000";
        
        -- test the following conditions
        --      * one axis transfer
        --      * 0x100 (256) entries
        --      * tx 128 entries
        --      * stall 1024 aclk cycles ( drain 1024 / 16.28  ~= 62.90 )
        --      * tx 64 entries ( ~128 entries in fifo )
        --      * stall 1024 aclk cycles ( drain ~= 62.90 )
        --      * tx 64 entries
        current := 0;
        axis_tx(s_axis_tvalid, s_axis_tdata, s_axis_tlast, data, current, 128); 
        axis_tx_stall(s_axis_tvalid, 1024);
        axis_tx(s_axis_tvalid, s_axis_tdata, s_axis_tlast, data, current, 192); 
        axis_tx_stall(s_axis_tvalid, 1024);
        axis_tx(s_axis_tvalid, s_axis_tdata, s_axis_tlast, data, current, 256);
        assert false report "transfer with stalls passed" severity NOTE;
        
        -- test the following conditions
        --      * two axis transfers
        --      * 0x200 (512) entries
        --      * no stalls
        current := 0;
        axis_tx(s_axis_tvalid, s_axis_tdata, s_axis_tlast, data, current, 512);
        assert false report "transfer without stalls passed" severity NOTE;
        
        -- test the following conditions
        --      * one axis transfer
        --      * 0x100 (256 entries)
        --      * start with fifo empty
        --      * stall for 10000 ( drain about 10000 / 16.28 ~= 614.25 entries )
        axis_tx_stall(s_axis_tvalid, 10000);
        current := 0;
        axis_tx(s_axis_tvalid, s_axis_tdata, s_axis_tlast, data, current, 256);
        assert false report "transfer from fifo empty passed" severity NOTE;
        
        -- test the following conditions
        --      * multiple axis transfers
        --      * 0x400 (1024 entries)
        --      * no stalls
        current := 0;
        axis_tx(s_axis_tvalid, s_axis_tdata, s_axis_tlast, data, current, 1024);
        assert false report "multiple transfers with no stalls passed" severity NOTE;
        
        assert false report "success" severity NOTE;
        
        wait;
    end process;
end behavioral;
