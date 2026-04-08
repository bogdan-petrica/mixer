-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mixer_top is
    port(
        -- clk  and reset signals
        signal aclk : in std_logic;
        signal rstn : in std_logic;
        signal mclk : in std_logic;
        signal mlatched : in std_logic;

        -- AXI4 LITE control interface signals
        --
        -- address read channel
        signal s_axi_arready : out std_logic;
        signal s_axi_arvalid : in std_logic;
        signal s_axi_araddr : in std_logic_vector(7 downto 0);
        signal s_axi_arprot : in std_logic_vector(2 downto 0);
        
        -- read channel 
        signal s_axi_rready : in std_logic;
        signal s_axi_rvalid : out std_logic;
        signal s_axi_rdata : out std_logic_vector(31 downto 0);
        signal s_axi_rresp : out std_logic_vector(1 downto 0);
        
        -- address write channel
        signal s_axi_awready : out std_logic;
        signal s_axi_awvalid : in std_logic;
        signal s_axi_awaddr : in std_logic_vector(7 downto 0);
        signal s_axi_awprot : in std_logic_vector(2 downto 0);
        
        -- write channel
        signal s_axi_wready : out std_logic;
        signal s_axi_wvalid : in std_logic;
        signal s_axi_wdata : in std_logic_vector(31 downto 0);
        signal s_axi_wstrb : in std_logic_vector(3 downto 0);
        
        -- wrtie response channel
        signal s_axi_bready : in std_logic;
        signal s_axi_bvalid : out std_logic;
        signal s_axi_bresp : out std_logic_vector(1 downto 0);
        -- end of AXI4 LITE control interface signals
        
        -- master AXIS
        signal m_axis_tdata : out std_logic_vector(31 downto 0);
        signal m_axis_tid : out std_logic_vector(2 downto 0);
        signal m_axis_tkeep : out std_logic_vector(3 downto 0);
        signal m_axis_tlast : out std_logic;
        signal m_axis_tready : in std_logic;
        signal m_axis_tvalid : out std_logic;
        
        -- slave AXIS
        signal s_axis_tdata : in std_logic_vector(31 downto 0);
        signal s_axis_tid : in std_logic_vector(2 downto 0);
        signal s_axis_tkeep : in std_logic_vector(3 downto 0);
        signal s_axis_tlast : in std_logic;
        signal s_axis_tready : out std_logic;
        signal s_axis_tvalid : in std_logic;
        
        -- i2s generic
        signal bclk : out std_logic;
        signal muten : out std_logic;
        
        -- i2s rx
        signal reclrc : out std_logic;
        signal recdat : in std_logic;
        
        -- i2s tx
        signal pblrc : out std_logic;
        signal pbdat : out std_logic
    );
end mixer_top;

architecture behavioral of mixer_top is
    attribute keep : string;

    signal aresetn : std_logic;
    signal mresetn : std_logic;

    -- ctrl write
    signal wr_en : std_logic;
    signal wr_addr : std_logic_vector(7 downto 0);
    signal wr_data : std_logic_vector(15 downto 0);
    
    -- ctrl read
    signal rd_en : std_logic;
    signal rd_addr : std_logic_vector(7 downto 0);
    signal rd_data : std_logic_vector(15 downto 0);
    
    -- rec2axis ctrl
    signal rec_act : std_logic;
    signal rec_size : std_logic_vector(15 downto 0);
    signal rec_en : std_logic;
        
    signal rec_done : std_logic;
    signal rec_en_status : std_logic;
    
    -- fifo
    signal fifo_rst : std_logic;
    signal fifo_ardy : std_logic;
    signal fifo_mrdy : std_logic;
    
    -- rec
    signal rec_sstb : std_logic; 
    signal rec_left : std_logic_vector(23 downto 0);
    signal rec_right : std_logic_vector(23 downto 0);
    signal rec_data : std_logic_vector(63 downto 0);
    
    -- ramp
    signal ramp_data : std_logic_vector(63 downto 0);
    attribute keep of ramp_data : signal is "true";
    
    -- ps
    signal ps_left : std_logic_vector(23 downto 0);
    signal ps_right : std_logic_vector(23 downto 0);
    signal ps_data : std_logic_vector(63 downto 0);
    attribute keep of ps_data: signal is "true";
    
    -- mic in
    signal mic_data : std_logic_vector(63 downto 0);
    
    -- delay
    signal delay_mux_sel : std_logic_vector(1 downto 0);
    signal delay_mux_data : std_logic_vector(63 downto 0);
    signal delay : std_logic_vector(15 downto 0);
    signal delay_di : std_logic_vector(31 downto 0);
    signal delay_do : std_logic_vector(31 downto 0);
    signal delay_data : std_logic_vector(63 downto 0);
    
    -- core
    signal core_sstb : std_logic;
    signal core_ramp_gain_sel : std_logic_vector(6 downto 0);
    signal core_ps_gain_sel : std_logic_vector(6 downto 0);
    signal core_mic_gain_sel : std_logic_vector(6 downto 0);
    signal core_delay_gain_sel : std_logic_vector(6 downto 0);
    
    -- pb
    signal pb_sstb : std_logic;
    attribute keep of pb_sstb: signal is "true";
    signal pb_data : std_logic_vector(63 downto 0);
    attribute keep of pb_data: signal is "true";

begin
    inst_axi2ctrl: entity work.axi2ctrl port map(
        aclk => aclk,
        aresetn => aresetn,
        
        -- address read channel
        s_axi_arready => s_axi_arready,
        s_axi_arvalid => s_axi_arvalid,
        s_axi_araddr => s_axi_araddr,
        s_axi_arprot => s_axi_arprot,
        
        -- read channel
        s_axi_rready => s_axi_rready,
        s_axi_rvalid => s_axi_rvalid,
        s_axi_rdata => s_axi_rdata,
        s_axi_rresp => s_axi_rresp,
        
        -- address write
        s_axi_awready => s_axi_awready,
        s_axi_awvalid => s_axi_awvalid,
        s_axi_awaddr => s_axi_awaddr,
        s_axi_awprot => s_axi_awprot,
            
        -- write channel
        s_axi_wready => s_axi_wready,
        s_axi_wvalid => s_axi_wvalid,
        s_axi_wdata => s_axi_wdata,
        s_axi_wstrb => s_axi_wstrb,
            
        -- wrtie response channel
        s_axi_bready => s_axi_bready,
        s_axi_bvalid => s_axi_bvalid,
        s_axi_bresp => s_axi_bresp,
        
        -- ctrl write
        wr_en => wr_en,
        wr_addr => wr_addr,
        wr_data => wr_data,

        -- ctrl read        
        rd_en => rd_en,
        rd_addr => rd_addr,
        rd_data => rd_data
    );
    
    inst_rst_ctrl : entity work.rst_ctrl port map(
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
    
    inst_ctrl: entity work.ctrl port map (
        aclk => aclk,
        aresetn => aresetn,
    
        wr_en => wr_en,
        wr_addr => wr_addr,
        wr_data => wr_data,
    
        rd_en => rd_en,
        rd_addr => rd_addr,
        rd_data => rd_data,
    
        rec_act => rec_act,
        rec_size => rec_size,
        rec_en => rec_en,
        
        rec_done => rec_done,
        rec_en_status => rec_en_status,
        
        mclk => mclk,
        mresetn => mresetn,
        
        pb_delay_mux_sel => delay_mux_sel,

        pb_ramp_gain_sel => core_ramp_gain_sel,
        pb_ps_gain_sel => core_ps_gain_sel,
        pb_mic_gain_sel => core_mic_gain_sel,
        pb_delay_gain_sel => core_delay_gain_sel,
        
        pb_delay => delay
    );
    
    inst_rec2axis : entity work.rec2axis port map(
        aclk => aclk,
        aresetn => aresetn,
        
        -- master AXIS
        m_axis_tdata => m_axis_tdata,
        m_axis_tid => m_axis_tid,
        m_axis_tkeep => m_axis_tkeep,
        m_axis_tlast => m_axis_tlast,
        m_axis_tready => m_axis_tready,
        m_axis_tvalid => m_axis_tvalid,
        
        -- fifo
        fifo_rst => fifo_rst,
        fifo_ardy => fifo_ardy,
        fifo_mrdy => fifo_mrdy,
        
        -- ctrl
        rec_act => rec_act,
        rec_size => rec_size,
        rec_en => rec_en,
        
        rec_done => rec_done,
        rec_en_status => rec_en_status,
        
        -- rec
        mclk => mclk,
        mresetn => mresetn,
        
        sstb => rec_sstb,
        left => rec_left,
        right => rec_right
    );
    
    rec_left <= rec_data(63 downto 40);
    rec_right <= rec_data(31 downto 8);
    
    inst_ramp_gen: entity work.ramp_gen port map(
        mclk => mclk,
        mresetn => mresetn,
        
        pb_data => ramp_data,
        pb_sstb => core_sstb
    );
    
    inst_axis2pb: entity work.axis2pb port map(
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
        
        sstb => core_sstb,
        left => ps_left,
        right => ps_right
    );
    
    ps_data <= ps_left & X"00" & ps_right & X"00";
    
    inst_rec2pb: entity work.rec2pb port map(
        mclk => mclk,
        mresetn => mresetn,
        
        rec_data => rec_data,
        rec_sstb => rec_sstb,
        
        pb_data => mic_data,
        pb_sstb => core_sstb
    );
    
    inst_delay_mux: entity work.delay_mux port map(
        sel => delay_mux_sel,
        
        ramp_in => ramp_data,
        ps_in => ps_data,
        mic_in => mic_data,
        core_in => pb_data,
        
        result => delay_mux_data
    );
    
    delay_di <= delay_mux_data(63 downto 48) & delay_mux_data(31 downto 16);
    
    inst_delay_line: entity work.delay_line port map(
        mclk => mclk,
        mresetn => mresetn,
        
        delay => delay,
        
        stb => core_sstb,
        di => delay_di,
        do => delay_do
    );
    
    delay_data <= delay_do(31 downto 16) & X"0000" & delay_do(15 downto 0) & X"0000";
    
    inst_core: entity work.core port map(
        mclk => mclk,
        mresetn => mresetn,
        
        ramp_gain_sel => core_ramp_gain_sel,
        ps_gain_sel => core_ps_gain_sel,
        mic_gain_sel => core_mic_gain_sel,
        delay_gain_sel => core_delay_gain_sel,
        
        sstb_out => core_sstb,
        ramp_in => ramp_data,
        ps_in => ps_data,
        mic_in => mic_data,
        delay_in => delay_data,
        
        sstb_in => pb_sstb,
        data_out => pb_data
    );
    
    inst_i2s: entity work.i2s port map(
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
end behavioral;
