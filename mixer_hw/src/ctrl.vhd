-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ctrl is
    port (
        signal aclk : in std_logic;
        signal aresetn : in std_logic;
        
        signal wr_en : in std_logic;
        signal wr_addr : in std_logic_vector(7 downto 0);
        signal wr_data : in std_logic_vector(15 downto 0);
        
        signal rd_en : in std_logic;
        signal rd_addr : in std_logic_vector(7 downto 0);
        signal rd_data : out std_logic_vector(15 downto 0);
        
        signal rec_act : out std_logic;
        signal rec_size : out std_logic_vector(15 downto 0);
        signal rec_en : out std_logic;
        
        signal rec_done : in std_logic;
        signal rec_en_status : in std_logic;
        
        -- mclk domain
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal pb_delay_mux_sel : out std_logic_vector(1 downto 0);
        
        signal pb_ramp_gain_sel : out std_logic_vector(6 downto 0);
        signal pb_ps_gain_sel : out std_logic_vector(6 downto 0);
        signal pb_mic_gain_sel : out std_logic_vector(6 downto 0);
        signal pb_delay_gain_sel : out std_logic_vector(6 downto 0);
        
        signal pb_delay : out std_logic_vector(15 downto 0)
    ); 
end ctrl;

architecture behavioral of ctrl is
    constant ADDR_WIDTH : integer := 8;

    attribute async_reg : string;

    constant REC_CONFIG_REG                 : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"00";
    constant REC_ACT_OFFSET                 : integer := 0;
    constant REC_EN_OFFSET                  : integer := 1;
    
    constant REC_STATUS_REG                 : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"04";
    constant REC_ACT_DONE_OFFSET            : integer := 0;
    constant REC_ACT_ERR_OFFSET             : integer := 1;
    
    constant REC_SIZE_REG                   : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"08";
    constant PB_DELAY_MUX_SEL_REG           : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"0C";
    constant PB_RAMP_GAIN_SEL_REG           : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"10";
    constant PB_PS_GAIN_SEL_REG             : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"14";
    constant PB_MIC_GAIN_SEL_REG            : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"18";
    constant PB_DELAY_GAIN_SEL_REG          : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"1C";
    
    constant PB_DELAY_REG                   : std_logic_vector(ADDR_WIDTH - 1 downto 0) := X"20";
    
    constant PB_RAMP_GAIN_SEL_DEFAULT       : std_logic_vector(6 downto 0) := "0000000";
    constant PB_PS_GAIN_SEL_DEFAULT         : std_logic_vector(6 downto 0) := "0000000";
    -- default value for gain is 0.0db or selector 0x73
    constant PB_MIC_GAIN_SEL_DEFAULT        : std_logic_vector(6 downto 0) := "1110011";
    constant PB_DELAY_GAIN_SEL_DEFAULT      : std_logic_vector(6 downto 0) := "0000000";
    
    signal ra : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    signal wa : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    
    signal rec_act_q : std_logic;
    signal rec_en_q : std_logic;
    
    signal rec_done_q : std_logic;
    signal rec_act_err_q : std_logic;
    
    signal rec_size_q : std_logic_vector(15 downto 0); 
    
    signal pb_delay_mux_sel_q : std_logic_vector(1 downto 0);
    
    signal pb_ramp_gain_sel_q : std_logic_vector(6 downto 0);
    signal pb_ps_gain_sel_q : std_logic_vector(6 downto 0);
    signal pb_mic_gain_sel_q : std_logic_vector(6 downto 0); 
    signal pb_delay_gain_sel_q : std_logic_vector(6 downto 0);
    
    signal pb_delay_q : std_logic_vector(15 downto 0);
    
    signal rec_config : std_logic_vector(15 downto 0);
    signal rec_status : std_logic_vector(15 downto 0);
    signal pb_delay_mux_sel_read : std_logic_vector(15 downto 0);
    signal pb_ramp_gain_sel_read : std_logic_vector(15 downto 0);
    signal pb_ps_gain_sel_read : std_logic_vector(15 downto 0);
    signal pb_mic_gain_sel_read : std_logic_vector(15 downto 0);
    signal pb_delay_gain_sel_read : std_logic_vector(15 downto 0);
    
    signal reg_read : std_logic_vector(15 downto 0);
    
    type SYNC is record
        delay_mux_sel : std_logic_vector(1 downto 0);
        ramp_gain_sel : std_logic_vector(6 downto 0);
        ps_gain_sel : std_logic_vector(6 downto 0);
        mic_gain_sel : std_logic_vector(6 downto 0);
        delay_gain_sel : std_logic_vector(6 downto 0);
        delay : std_logic_vector(15 downto 0);
    end record;
    
    signal sync0 : SYNC;
    attribute async_reg of sync0: signal is "true";
    
    signal sync1 : SYNC;
    attribute async_reg of sync1: signal is "true";
begin
    ra <= rd_addr(ADDR_WIDTH - 1 downto 2) & "00";
    wa <= wr_addr(ADDR_WIDTH - 1 downto 2) & "00"; 

    rec_config <= "00000000000000" & rec_en_q & rec_act_q;
    rec_status <= "0000000000000" & rec_en_status & rec_act_err_q & rec_done_q;
    rec_size <= rec_size_q;
    pb_delay_mux_sel_read <= "00000000000000" & pb_delay_mux_sel_q;
    pb_ramp_gain_sel_read <= "000000000" & pb_ramp_gain_sel_q;
    pb_ps_gain_sel_read <= "000000000" & pb_ps_gain_sel_q;
    pb_mic_gain_sel_read <= "000000000" & pb_mic_gain_sel_q;
    pb_delay_gain_sel_read <= "000000000" & pb_delay_gain_sel_q;
    
    with ra select reg_read <=
        rec_config when REC_CONFIG_REG,
        rec_status when REC_STATUS_REG,
        rec_size_q when REC_SIZE_REG,
        pb_delay_mux_sel_read when PB_DELAY_MUX_SEL_REG,
        pb_ramp_gain_sel_read when PB_RAMP_GAIN_SEL_REG,
        pb_ps_gain_sel_read when PB_PS_GAIN_SEL_REG,
        pb_mic_gain_sel_read when PB_MIC_GAIN_SEL_REG,
        pb_delay_gain_sel_read when PB_DELAY_GAIN_SEL_REG,
        pb_delay_q when PB_DELAY_REG,
        (others => '0') when others;
        
    read: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            rd_data <= (others => '0');
        elsif rising_edge(aclk) then
            rd_data <= reg_read;
        end if;
    end process read;
    
    -- rec_act bit
    act: process(aclk, aresetn)
        variable act_req : boolean;
    begin
        if aresetn = '0' then
            rec_act_q <= '0';
            rec_done_q <= '0';
            rec_act_err_q <= '0';
        elsif rising_edge(aclk) then
            act_req := (wr_en = '1') and (wa = REC_CONFIG_REG) and (wr_data(REC_ACT_OFFSET) = '1');
            
            if rec_act_q = '0' then
                if act_req then
                    rec_act_q <= '1';
                    rec_done_q <= '0';
                    rec_act_err_q <= '0';
                end if;
            else
                if act_req then
                    rec_act_err_q <= '1';
                end if;
            
                if rec_done = '1' then
                    rec_act_q <= '0';
                    rec_done_q <= '1';
                end if;
            end if;
        end if;
    end process act;
    
    rec_act <= rec_act_q;
    
    -- rec_en bit
    en: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            rec_en_q <= '0';
        elsif rising_edge(aclk) then
            if (wr_en = '1') and (wa = REC_CONFIG_REG) and (wr_data(REC_EN_OFFSET) = '1') then
                rec_en_q <= not rec_en_q;
            end if;
        end if;
    end process en;
    
    rec_en <= rec_en_q;
    
    -- rec_size register
    size: process(aclk, aresetn)
    begin   
        if aresetn = '0' then
            rec_size_q <= (others => '0');
        elsif rising_edge(aclk) then
            if (wr_en = '1') and (wa = REC_SIZE_REG) then
                rec_size_q <= wr_data;
            end if; 
        end if;
    end process size;
    
    -- pb_delay_mux_sel register
    mux_sel: process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                pb_delay_mux_sel_q <= "00";
            else
                if (wr_en = '1') and (wa = PB_DELAY_MUX_SEL_REG) then
                    pb_delay_mux_sel_q <= wr_data(1 downto 0);
                end if;
            end if;
        end if;
    end process mux_sel;
    
    -- pb_[ramp|ps|mic|delay]_gain_sel registers
    ramp_gain_sel: process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                pb_ramp_gain_sel_q <= PB_RAMP_GAIN_SEL_DEFAULT;
                pb_ps_gain_sel_q <= PB_PS_GAIN_SEL_DEFAULT;
                pb_mic_gain_sel_q <= PB_MIC_GAIN_SEL_DEFAULT;
                pb_delay_gain_sel_q <= PB_DELAY_GAIN_SEL_DEFAULT;
            else
                if (wr_en = '1') and (wa = PB_RAMP_GAIN_SEL_REG) then
                    pb_ramp_gain_sel_q <= wr_data(6 downto 0);
                end if;
                
                if (wr_en = '1') and (wa = PB_PS_GAIN_SEL_REG) then
                    pb_ps_gain_sel_q <= wr_data(6 downto 0);
                end if;
                
                if (wr_en = '1') and (wa = PB_MIC_GAIN_SEL_REG) then
                    pb_mic_gain_sel_q <= wr_data(6 downto 0);
                end if;
                
                if (wr_en = '1') and (wa = PB_DELAY_GAIN_SEL_REG) then
                    pb_delay_gain_sel_q <= wr_data(6 downto 0);
                end if;
            end if;
        end if;
    end process ramp_gain_sel;
    
    -- pb_delay register
    delay_reg: process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                pb_delay_q <= (others => '0');
            else
                if (wr_en = '1') and (wa = PB_DELAY_REG) then
                    pb_delay_q <= wr_data(15 downto 0);
                end if;
            end if;
        end if;
    end process delay_reg;
    
    -- synchronizer to the mclk domain
    mclk_sync: process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                sync0 <= (others => (others => '0'));
                sync1 <= (others => (others => '0'));
            else
                sync0 <= (
                            pb_delay_mux_sel_q,
                            pb_ramp_gain_sel_q,
                            pb_ps_gain_sel_q,
                            pb_mic_gain_sel_q,
                            pb_delay_gain_sel_q,
                            pb_delay_q);
                sync1 <= sync0;
            end if;
        end if;
    end process mclk_sync;
    
    pb_delay_mux_sel <= sync1.delay_mux_sel;
    pb_ramp_gain_sel <= sync1.ramp_gain_sel;
    pb_ps_gain_sel <= sync1.ps_gain_sel;
    pb_mic_gain_sel <= sync1.mic_gain_sel;
    pb_delay_gain_sel <= sync1.delay_gain_sel;
    pb_delay <= sync1.delay;
end behavioral;


