-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_rst_ctrl is
end tb_rst_ctrl;

architecture behavioral of tb_rst_ctrl is
    signal aclk : std_logic;
    signal rstn : std_logic;
        
    signal mclk : std_logic;
    signal mlatched : std_logic;
    
    signal aresetn : std_logic;
    signal mresetn : std_logic;
    
    signal fifo_rst : std_logic;
    signal fifo_ardy : std_logic;
    signal fifo_mrdy : std_logic;
    
    constant ARESETN_CYCLES : integer := 16;
    constant MRESETN_CYCLES : integer := 4;
    
    constant FIFO_RST_CYCLES : integer := 5;
    constant RDY_CYCLES : integer := 2;
    constant FF_CYCLES : integer := 2;
begin

    uut: entity work.rst_ctrl port map(
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
    
    verify_aclk: process(aclk, rstn, mlatched)
        variable cnt : integer;
        variable fifo_rst_cnt : integer;
    begin
        if rstn = '0' or mlatched = '0' then
            cnt := 0;
            fifo_rst_cnt := -1;
        elsif rising_edge(aclk) then
            assert (aresetn = '0') = (cnt < ARESETN_CYCLES) report "aresetn invalid" severity FAILURE;
            cnt := cnt + 1;
            if aresetn = '1' then
                if fifo_rst_cnt = -1 then
                    if fifo_rst = '0' then
                        fifo_rst_cnt := cnt;
                    end if;
                end if;
                
                if fifo_rst_cnt /= -1 then
                    assert fifo_rst = '0' report "fifo_rst outside reset" severity FAILURE;
                    assert (fifo_ardy = '1') = ((cnt - fifo_rst_cnt) >= RDY_CYCLES + FF_CYCLES) report "fifo_ardy invalid" severity FAILURE;
                else
                    assert fifo_ardy = '0' report "fifo_ardy invalid" severity FAILURE;
                end if;
            end if;
            
        end if;
    end process;

    verify_mclk: process(mclk, rstn, mlatched)
        variable cnt : integer;
    begin
        if rstn = '0' or mlatched = '0' then
            cnt := 0;
        elsif rising_edge(mclk) then
            assert (mresetn = '0') = (cnt < MRESETN_CYCLES) report "mresetn invalid" severity FAILURE;
            if mresetn = '1' then
                assert (fifo_rst = '1') = (cnt < MRESETN_CYCLES + FIFO_RST_CYCLES) report "fifo_rst invalid" severity FAILURE;
                assert (fifo_mrdy = '0') = (cnt < MRESETN_CYCLES + FIFO_RST_CYCLES + RDY_CYCLES) report "fifo_mrdy invalid" severity FAILURE;
            end if;        
            cnt := cnt + 1;
        end if;
    end process verify_mclk;
    
    stimulus: process
        variable acnt : integer;
        variable mcnt : integer;
    begin
        rstn <= '1';
        mlatched <= '0';
        
        loop
            wait until rising_edge(aclk) or rising_edge(mclk);
            
            exit when aresetn = '0' and mresetn = '0';
        end loop;
        
        wait for 2ns;
        
        rstn <= '1';
        mlatched <= '1';
   
        acnt := 0;
        mcnt := 0;
        loop
            wait until rising_edge(aclk) or rising_edge(mclk);
            if rising_edge(aclk) then
                acnt := acnt + 1;
            end if;
                
            if rising_edge(mclk) then
                mcnt := mcnt + 1;
            end if;
            
            exit when acnt > 1000 or mcnt > 1000;
        end loop;
        
        assert false report "success" severity NOTE;
        
        wait;
    end process stimulus;

end behavioral;

