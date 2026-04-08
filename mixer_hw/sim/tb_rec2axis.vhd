-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.math_real.all;

entity tb_rec2axis is
end tb_rec2axis;

architecture behavioral of tb_rec2axis is
    signal aclk : std_logic;
    signal rstn : std_logic;
    signal aresetn : std_logic;
    
    -- master axis
    signal m_axis_tdata : std_logic_vector(31 downto 0);
    signal m_axis_tid : std_logic_vector(2 downto 0);
    signal m_axis_tkeep : std_logic_vector(3 downto 0);
    signal m_axis_tlast : std_logic;
    signal m_axis_tready : std_logic;
    signal m_axis_tvalid : std_logic;
    
    -- fifo
    signal fifo_rst : std_logic;
    signal fifo_ardy : std_logic;
    signal fifo_mrdy : std_logic;
    
    -- ctrl
    signal rec_act : std_logic;
    signal rec_size : std_logic_vector(15 downto 0);
    signal rec_en : std_logic;
    
    signal rec_done : std_logic;
    signal rec_en_status : std_logic;
    
    signal rec_full_cnt : std_logic_vector(15 downto 0);
    
    -- rec
    signal mclk : std_logic;
    signal mlatched : std_logic;
    signal mresetn : std_logic;
    
    signal sstb : std_logic; 
    signal left : std_logic_vector(23 downto 0);
    signal right : std_logic_vector(23 downto 0);
    
    type RecvState is record
        count : unsigned(15 downto 0);
        total : unsigned(15 downto 0);
        have_prev : boolean;
        prev : unsigned(15 downto 0);
        gaps : unsigned(15 downto 0);
        active : integer;
        passive : integer;
    end record;
    
    type AxisRecvOut is record
        tready : std_logic;
        act : std_logic;
        size : std_logic_vector(15 downto 0);
    end record;
    
    function axis_recv_init(total : unsigned(15 downto 0);
        active, passive: integer) return RecvState is
    begin
        assert total > 0 report "invalid total" severity FAILURE;
        assert active > 0 report "invalid active" severity FAILURE;
        assert passive > 0 report "invalid passive" severity FAILURE;
        return (X"0000", total, false, X"0000", X"0000", active, passive);
    end function axis_recv_init;
    
    procedure axis_recv(signal recv_out : out AxisRecvOut;
        state : inout RecvState;
        new_count : in unsigned(15 downto 0) ) is
        variable left, right : unsigned(15 downto 0);
        variable steps : integer;
        variable i : integer;
        
        variable prev_tdata : std_logic_vector(31 downto 0);
        variable prev_tvalid : std_logic;
    begin
        assert state.count < new_count report "invalid call" severity FAILURE;
        assert new_count <= state.total report "invalid call" severity FAILURE;
        
        if m_axis_tvalid = '1' then
            if state.count + 1 = state.total then
                assert m_axis_tlast = '1' report "invalid m_axis_tlast, expected high" severity FAILURE;
            else
                assert m_axis_tlast = '0' report "invalid m_axis_tlast, expected low" severity FAILURE;
            end if;
        end if;
        assert rec_done = '0' report "invalid rec_done" severity FAILURE;
        
        if state.count = 0 then
            recv_out.act <= '1';
            recv_out.size <= std_logic_vector(state.total);
            wait until rising_edge(aclk);
        end if;
        
        while state.count < new_count loop
            steps := to_integer(new_count - state.count);
            if steps >= state.active then
                steps := state.active;
            end if;
            
            recv_out.tready <= '1';
            for i in 0 to (steps - 1) loop
                wait until rising_edge(aclk) and m_axis_tvalid = '1';
                state.count := state.count + 1;
                
                left := unsigned(m_axis_tdata(31 downto 16));
                right := unsigned(m_axis_tdata(15 downto 0));
                
                assert right = X"0000" report "invalid m_axis_tdata, right channel non zero" severity FAILURE;
                
                if state.have_prev then
                    assert state.prev < left report "invalid m_axis_tdata, expect monotonic seq" severity FAILURE;
                    state.gaps := state.gaps + (left - 1 - state.prev);
                end if;
                
                state.prev := left;
                state.have_prev := true;
                    
                if (state.count = state.total) then
                    assert (m_axis_tlast = '1') report "invalid m_axis_tlast, expected high" severity FAILURE;
                else
                    assert (m_axis_tlast = '0') report "invalid m_axis_tlast, expected low" severity FAILURE;
                end if;
                
                assert rec_done = '0' report "invalid rec_done" severity FAILURE;
            end loop;
            
            prev_tvalid := '0';
            
            recv_out.tready <= '0';
            for i in 0 to (state.passive - 1) loop
                wait until rising_edge(aclk);

                if (state.count = state.total) then
                    assert m_axis_tvalid = '0' report "invalid m_axis_tvalid, expected low" severity FAILURE;
                    assert rec_done = '1' report "invalid rec_done" severity FAILURE;
                else
                    if prev_tvalid = '1' then
                        assert m_axis_tvalid = '1' report "m_axis_tvalid went down while m_axis_tready=0" severity FAILURE;
                        assert m_axis_tdata = prev_tdata report "m_axis_tdata changing while m_axis_tready=0" severity FAILURE;
                    end if;
                
                    if m_axis_tvalid = '1' then
                        if (state.count + 1 = state.total) then
                            assert (m_axis_tlast = '1') report "invalid m_axis_tlast, expected high" severity FAILURE;
                        else
                            assert (m_axis_tlast = '0') report "invalid m_axis_tlast, expected low" severity FAILURE;
                        end if;
                    end if;
                    
                    prev_tdata := m_axis_tdata;
                    prev_tvalid := m_axis_tvalid;
                end if;
            end loop;
        end loop;
        
        if (state.count = state.total) then
            recv_out.act <= '0';
            wait until rising_edge(aclk);
            assert rec_done = '1' report "invalid rec_done" severity FAILURE;
            
            wait until rising_edge(aclk);
            assert rec_done = '0' report "invalid rec_done" severity FAILURE; 
        end if;
    end procedure axis_recv;
    
    signal recv_out : AxisRecvOut;
    
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

    uut : entity work.rec2axis port map (
        aclk => aclk,
        aresetn => aresetn,
        m_axis_tdata => m_axis_tdata, 
        m_axis_tid => m_axis_tid,
        m_axis_tkeep => m_axis_tkeep,
        m_axis_tlast => m_axis_tlast,
        m_axis_tready => m_axis_tready,
        m_axis_tvalid => m_axis_tvalid,
        fifo_rst => fifo_rst,
        fifo_ardy => fifo_ardy,
        fifo_mrdy => fifo_mrdy,
        rec_act => rec_act,
        rec_size => rec_size,
        rec_en => rec_en,
        rec_done => rec_done,
        rec_en_status => rec_en_status,
        rec_full_cnt => rec_full_cnt,
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
    
    sample_gen: process
        variable i : integer;
        
        variable left_cnt : unsigned(23 downto 0);
    begin
        wait until rising_edge(mclk) and mresetn = '1';
    
        left_cnt := X"000000";

        sstb <= '0';
        left <= std_logic_vector(left_cnt);
        right <= (others => '0');
    
        loop
            for i in 0 to 0 loop
                wait until rising_edge(mclk);
            end loop;

            left_cnt := left_cnt + X"000100";
            
            sstb <= '1';
            left <= std_logic_vector(left_cnt);
            wait until rising_edge(mclk);
            
            sstb <= '0';
        end loop;
    end process;
    
    rec_act <= recv_out.act;
    rec_size <= recv_out.size;
    m_axis_tready <= recv_out.tready;
    
    stimulus: process
        variable i : integer;
        variable recv_state : RecvState;
    begin
        -- aclk_freq / mclk_freq = (1 / 10ns) / ( 1 / 81.38 ) = 8.138
        -- sstb is active every other mclk period
        -- aclk_freq / sstb_freq = (1 / 10ns ) / ( 1 / ( 2 * 81.38 ) ) =  16.28
        rstn <= '0';
        mlatched <= '0';
        wait for 100ns;
        
        rstn <= '1';
        mlatched <= '1';
        wait for 100ns;
        
        -- test the following conditions
        --      * one transfer
        --      * 0x0400 entries (1024)
        --      * up to 32 aclk cycles transfer 
        --      * 256 aclk cycle transfer stalls( ~15.72 samples added per each stall ) 
        --      * stall for 10000 aclk cycles ~= 614.25 entries ( fifo has capacity for 512 entries )
        --      * at least ~102 samples will be lost
        rec_en <= '1';
        wait until rising_edge(aclk);
        
        recv_state := axis_recv_init(X"0400", 32, 256);
        axis_recv(recv_out, recv_state, X"0100");
        
        for i in 0 to 10000 loop
            wait until rising_edge(aclk);
        end loop;
        
        axis_recv(recv_out, recv_state, X"0108");
        axis_recv(recv_out, recv_state, X"0200");
        axis_recv(recv_out, recv_state, X"0300");
        
        axis_recv(recv_out, recv_state, X"0324");
        axis_recv(recv_out, recv_state, X"03ff");
        axis_recv(recv_out, recv_state, X"0400");
        
        rec_en <= '0';
        wait until rising_edge(aclk) and rec_en_status = '0';
        
        assert recv_state.gaps >= 102 report "expected more gaps" severity FAILURE;
        assert recv_state.gaps <= unsigned(rec_full_cnt) report "invalid recv_full_cnt" severity FAILURE;
        
        assert false report "big multi chunk transfer with stalls passed" severity NOTE;
        
        -- test back to back normal transfers
        --      * two transfers
        --      * 0x0100 entries
        --      * up to 0x0100 aclk cycle transfers
        --      * 1 aclk cycle stall
        rec_en <= '1';
        wait until rising_edge(aclk);
        
        recv_state := axis_recv_init(X"0100", 256, 1);
        axis_recv(recv_out, recv_state, X"0100");
        
        recv_state := axis_recv_init(X"0100", 256, 1);
        axis_recv(recv_out, recv_state, X"0100");
        
        rec_en <= '0';
        wait until rising_edge(aclk) and rec_en_status = '0';
        
        assert recv_state.gaps = 0 report "unexpected gaps" severity FAILURE;
        
        assert false report "back to back simple transfers passed" severity NOTE;
        
        -- test back to back uninterrupted transfers
        --      * two transfers
        --      * stall for 10000 aclk cycles (~= 614.25 samples, see above)
        --      * up to 0x100 aclk cycle transfers
        --      * 1 aclk cycle stall
        rec_en <= '1';
        wait until rising_edge(aclk) and rec_en_status = '1';
        
        for i in 0 to 10000 loop
            wait until rising_edge(aclk);
        end loop;
        
        recv_state := axis_recv_init(X"0100", 256, 1);
        axis_recv(recv_out, recv_state, X"0100");
        
        recv_state := axis_recv_init(X"0100", 256, 1);
        axis_recv(recv_out, recv_state, X"0100");
        
        rec_en <= '0';
        wait until rising_edge(aclk) and rec_en_status = '0';
        
        assert recv_state.gaps = 0 report "unexpected gaps" severity FAILURE;
        
        assert false report "back to back uninterrupted transfers passed" severity NOTE;
        
        -- test rec_en reenable during drain
        --      * no transfer
        --      * stall for 10000 cycles ( ~= 614.25 samples, see above )
        --      * pull rec_en low
        --      * stall for 100 cycles ( <100 samples drained )
        --      * pull rec_en high
        --      * stall for 2000 cycles ( ~= 122.8 samples, fifo full again )
        --      * pull rec_en low and wait for full drain 
        rec_en <= '1';
        wait until rising_edge(aclk) and rec_en_status = '1';
        
        for i in 0 to 10000 loop
            wait until rising_edge(aclk);
        end loop;
        
        rec_en <= '0';
        wait until rising_edge(aclk);
        
        for i in 0 to 100 loop
            wait until rising_edge(aclk);
        end loop;
        
        assert rec_en_status = '1' report "invalid rec_en_status" severity FAILURE;
            
        rec_en <= '1';
        wait until rising_edge(aclk);
        
        for i in 0 to 2000 loop
            wait until rising_edge(aclk);
        end loop;
        
        assert rec_en_status = '1' report "invalid rec_en_status" severity FAILURE;
        
        rec_en <= '0';
        wait until rising_edge(aclk) and rec_en_status = '0';
        
        assert false report "test rec_en high during drain passed" severity NOTE;
        
        -- test with rec_act just after rec_done
        -- test with rec_en disable/rec_en enable while in run
        --      ( this must be concurrent, ok, could be done if I prefill the fifo )

        assert false report "success" severity NOTE;

        wait;
    end process stimulus;

end behavioral;
