-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axi2ctrl is
    port(
        aclk : in std_logic;
        aresetn : in std_logic;
        
        -- address read channel
        s_axi_arready : out std_logic;
        s_axi_arvalid : in std_logic;
        s_axi_araddr : in std_logic_vector(7 downto 0);
        s_axi_arprot : in std_logic_vector(2 downto 0);
        
        -- read channel 
        s_axi_rready : in std_logic;
        s_axi_rvalid : out std_logic;
        s_axi_rdata : out std_logic_vector(31 downto 0);
        s_axi_rresp : out std_logic_vector(1 downto 0);
        
        -- address write channel
        s_axi_awready : out std_logic;
        s_axi_awvalid : in std_logic;
        s_axi_awaddr : in std_logic_vector(7 downto 0);
        s_axi_awprot : in std_logic_vector(2 downto 0);
        
        -- write channel
        s_axi_wready : out std_logic;
        s_axi_wvalid : in std_logic;
        s_axi_wdata : in std_logic_vector(31 downto 0);
        s_axi_wstrb : in std_logic_vector(3 downto 0);
        
        -- wrtie response channel
        s_axi_bready : in std_logic;
        s_axi_bvalid : out std_logic;
        s_axi_bresp : out std_logic_vector(1 downto 0);
        
        -- ctrl write
        wr_en : out std_logic;
        wr_addr : out std_logic_vector(7 downto 0);
        wr_data : out std_logic_vector(15 downto 0);
        
        -- ctrl read
        rd_en : out std_logic;
        rd_addr : out std_logic_vector(7 downto 0);
        rd_data : in std_logic_vector(15 downto 0)
    );
end axi2ctrl;

architecture behavioral of axi2ctrl is

    constant OKAY : std_logic_vector(1 downto 0) := "00";

    constant ReadStateIdle : std_logic_vector(1 downto 0) := "00";
    constant ReadStateAddr : std_logic_vector(1 downto 0) := "01";
    constant ReadStateDataWait : std_logic_vector(1 downto 0) := "10";
    constant ReadStateData : std_logic_vector(1 downto 0) := "11";

    signal read_state : std_logic_vector(1 downto 0);
    signal read_addr : std_logic_vector(7 downto 0);
    signal read_data : std_logic_vector(15 downto 0);
    
    signal write_have_addr : std_logic;
    signal write_have_data : std_logic; 
    signal write_disable : std_logic;
    
    signal write_addr : std_logic_vector(7 downto 0);
    signal write_data: std_logic_vector(15 downto 0);

begin
    read: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            read_state <= ReadStateIdle;
            read_addr <= (others => '0');
            read_data <= (others => '0');
        elsif rising_edge(aclk) then
            case read_state is
                when ReadStateIdle =>
                    if s_axi_arvalid = '1' then
                        read_addr <= s_axi_araddr;
                        read_state <= ReadStateAddr;
                    end if;
                when ReadStateAddr =>
                    read_state <= ReadStateDataWait;
                when ReadStateDataWait =>
                    read_data <= rd_data;
                    read_state <= ReadStateData;
                when ReadStateData =>
                    if s_axi_rready = '1' then
                        read_state <= ReadStateIdle;
                    end if;
                when others =>
                    read_state <= read_state;
            end case; 
        end if;
    end process read;
    
    s_axi_arready <= '1' when read_state = ReadStateIdle else '0';
    s_axi_rvalid <= '1' when read_state = ReadStateData else '0';
    s_axi_rdata <= X"0000" & read_data;
    s_axi_rresp <= OKAY;
    
    rd_en <= '1' when read_state = ReadStateAddr else '0';
    rd_addr <= read_addr;
    
    write: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            write_have_addr <= '0';
            write_have_data <= '0';
            write_disable <= '0';
            
            write_addr <= (others => '0');
            write_data <= (others => '0');
        elsif rising_edge(aclk) then
            if write_have_addr = '0' then
                if s_axi_awvalid = '1' then
                    write_addr <= s_axi_awaddr;
                    write_have_addr <= '1';
                end if;
            end if;
            
            if write_have_data = '0' then
                if s_axi_wvalid = '1' then
                    write_data <= s_axi_wdata(15 downto 0);
                    write_have_data <= '1';
                end if;
            end if;
            
            if write_have_addr = '1' and write_have_data = '1' then
                if s_axi_bready = '1' then
                    write_have_addr <= '0';
                    write_have_data <= '0';
                    write_disable <= '0';
                else
                    write_disable <= '1';             
                end if;
            end if;
        end if;
    end process write;
    
    s_axi_awready <= not write_have_addr;
    s_axi_wready <= not write_have_data;
    s_axi_bvalid <= write_have_addr and write_have_data;
    s_axi_bresp <= OKAY;
    
    wr_en <= (write_have_addr and write_have_data) and not write_disable;
    wr_addr <= write_addr;
    wr_data <= write_data;
end behavioral;
