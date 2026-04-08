-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_axi2ctrl is
end tb_axi2ctrl;

architecture behavioral of tb_axi2ctrl is
    signal aclk : std_logic;
    signal aresetn : std_logic;
    
    -- address read channel
    signal s_axi_arready : std_logic;
    signal s_axi_arvalid : std_logic;
    signal s_axi_araddr : std_logic_vector(7 downto 0);
    signal s_axi_arprot : std_logic_vector(2 downto 0);
    
    -- read channel 
    signal s_axi_rready : std_logic;
    signal s_axi_rvalid : std_logic;
    signal s_axi_rdata : std_logic_vector(31 downto 0);
    signal s_axi_rresp : std_logic_vector(1 downto 0);
    
    -- address write channel
    signal s_axi_awready : std_logic;
    signal s_axi_awvalid : std_logic;
    signal s_axi_awaddr : std_logic_vector(7 downto 0);
    signal s_axi_awprot : std_logic_vector(2 downto 0);
    
    -- write channel
    signal s_axi_wready : std_logic;
    signal s_axi_wvalid : std_logic;
    signal s_axi_wdata : std_logic_vector(31 downto 0);
    signal s_axi_wstrb : std_logic_vector(3 downto 0);
    
    -- wrtie response channel
    signal s_axi_bready : std_logic;
    signal s_axi_bvalid : std_logic;
    signal s_axi_bresp : std_logic_vector(1 downto 0);
    
    -- ctrl write
    signal wr_en : std_logic;
    signal wr_addr : std_logic_vector(7 downto 0);
    signal wr_data : std_logic_vector(15 downto 0);
    
    -- ctrl read
    signal rd_en : std_logic;
    signal rd_addr : std_logic_vector(7 downto 0);
    signal rd_data : std_logic_vector(15 downto 0);
    
    type s_axi_out is record
        -- address read channel
        arvalid : std_logic;
        araddr : std_logic_vector(7 downto 0);
        
        -- read channel
        rready : std_logic;
        
        -- address write channel
        awvalid : std_logic;
        awaddr : std_logic_vector(7 downto 0);
        
        -- write channel
        wvalid : std_logic;
        wdata : std_logic_vector(31 downto 0);
        
        -- write response channel
        bready : std_logic;
    end record;
    
    type TRANS_STATE is (Idle, Waiting, Done);
    
    shared variable ar_cycle : integer := 1;
    shared variable r_cycle : integer := 1;
    
    procedure axi_rd(signal s_axi : out s_axi_out;
        addr : in std_logic_vector(7 downto 0);
        data : out std_logic_vector(15 downto 0)) is
        
        variable cycle : integer;
        
        variable arvalid : TRANS_STATE;
        variable rready : TRANS_STATE;
        
        variable valid : boolean;
        variable data_tmp : std_logic_vector(15 downto 0);
    begin
        assert ar_cycle > 0 report "precondition" severity FAILURE;
        assert r_cycle > 0 report "precondition" severity FAILURE;
        
        valid := false;

        arvalid := Idle;
        s_axi.arvalid <= '0';
        s_axi.araddr <= addr;
        
        rready := Idle;
        s_axi.rready <= '0';
        
        for cycle in 0 to 10 loop
            wait until rising_edge(aclk);
            
            assert not (s_axi_rvalid = '1' and arvalid /= Done) report "read accepted early" severity FAILURE;
            
            if s_axi_rvalid = '1' then
                if valid then
                    assert data_tmp = s_axi_rdata(15 downto 0) report "read data changing" severity FAILURE;
                else
                    data_tmp := s_axi_rdata(15 downto 0);
                    valid := true;
                end if;
            end if;
        
            case arvalid is
                when Idle =>
                    if cycle = ar_cycle then
                        arvalid := Waiting;
                        s_axi.arvalid <= '1';
                    end if;
                when Waiting =>
                    if s_axi_arready = '1' then
                        arvalid := Done;
                        s_axi.arvalid <= '0';
                    end if;
                when others =>
            end case;
            
            case rready is
                when Idle =>
                    if cycle = r_cycle then
                        rready := Waiting;
                        s_axi.rready <= '1';
                    end if;
                when Waiting =>
                    if s_axi_rvalid = '1' then
                        rready := Done;
                        s_axi.rready <= '0';
                        data := s_axi_rdata(15 downto 0);
                    end if;
                when others =>
            end case;
            
            exit when arvalid = Done and rready = Done;
        end loop;
        
        assert cycle < 10 report "read does not finish" severity FAILURE;
    end procedure axi_rd;         
    
    shared variable aw_cycle : integer := 1;
    shared variable w_cycle : integer := 1;
    shared variable b_cycle : integer := 1;
    
    procedure axi_wr(signal s_axi : out s_axi_out;
        addr : in std_logic_vector(7 downto 0);
        data : in std_logic_vector(15 downto 0)) is
        
        variable cycle : integer;
        
        variable awvalid : TRANS_STATE;
        variable wvalid : TRANS_STATE;
        variable bready : TRANS_STATE;
    begin
        assert aw_cycle > 0 report "precondition" severity FAILURE;
        assert w_cycle > 0 report "precondition" severity FAILURE;
        assert b_cycle > 0 report "precondition" severity FAILURE;
    
        awvalid := Idle;
        s_axi.awvalid <= '0';
        s_axi.awaddr <= addr;
        
        wvalid := Idle;
        s_axi.wvalid <= '0';
        s_axi.wdata <= X"0000" & data;
        
        bready := Idle;
        s_axi.bready <= '0';
        
        for cycle in 0 to 10 loop
            wait until rising_edge(aclk);
            
            assert not (s_axi_bvalid = '1' and (awvalid /= Done or wvalid /= Done)) report "write accepted early" severity FAILURE;
            
            case awvalid is
                when Idle =>
                    if cycle = aw_cycle then
                        awvalid := Waiting;
                        s_axi.awvalid <= '1';
                    end if;
                when Waiting =>
                    if s_axi_awready = '1' then
                        awvalid := Done;
                        s_axi.awvalid <= '0';
                    end if;
                when others =>
            end case;
            
            case wvalid is
                when Idle =>
                    if cycle = w_cycle then
                        wvalid := Waiting;
                        s_axi.wvalid <= '1';
                    end if;
                when Waiting =>
                    if s_axi_wready = '1' then
                        wvalid := Done;
                        s_axi.wvalid <= '0';
                    end if;
                when others =>
            end case;
            
            case bready is
                when Idle =>
                    if cycle = b_cycle then
                        bready := Waiting;
                        s_axi.bready <= '1';
                    end if;
                when Waiting =>
                    if s_axi_bvalid = '1' then
                        bready := Done;
                        s_axi.bready <= '0';
                    end if;
                when others =>
            end case;
            
            exit when awvalid = Done and wvalid = Done and bready = Done; 
        end loop;
        
        assert cycle < 10 report "write does not finish" severity FAILURE;
    end procedure axi_wr;
    
    type CYCLES is record
        ar_cycle : integer;
        r_cycle : integer;
        aw_cycle : integer;
        w_cycle : integer;
        b_cycle : integer;
    end record;
    
    type CYCLES_ARR is array (natural range <>) of CYCLES;
    
    signal s_axi : s_axi_out;
    
    type REGS_TYPE is array(0 to 63) of std_logic_vector(15 downto 0);
    
    signal regs : REGS_TYPE;
    signal wa : std_logic_vector(7 downto 0);
    signal ra : std_logic_vector(7 downto 0);
    
    constant tb_cycles : CYCLES_ARR := 
    (
        (1, 1, 1, 1, 1),    -- ideal
        (1, 2, 1, 1, 1),    -- rready delayed
        (1, 6, 1, 1, 1),    -- rready further delayed
        
        (1, 1, 2, 1, 1),    -- awvalid delayed
        (1, 1, 1, 2, 1),    -- wvalid delayed
        
        (1, 1, 2, 1, 2),    -- awvalid, bready same cycle, wvalid early
        (1, 1, 1, 2, 2),    -- wvalid, bready same cycle, aw early
        
        (1, 1, 2, 1, 3),    -- awvalid delayed, bready last
        (1, 1, 1, 2, 3),    -- wvalid delayed, bready last
        
        (1, 1, 3, 2, 1),    -- awvalid delayed, bready first
        (1, 1, 2, 3, 1)     -- wvalid delayed, bready first
    );
begin

    s_axi_arvalid <= s_axi.arvalid;
    s_axi_araddr <= s_axi.araddr;
    s_axi_rready <= s_axi.rready;
    s_axi_awvalid <= s_axi.awvalid;
    s_axi_awaddr <= s_axi.awaddr;
    s_axi_wvalid <= s_axi.wvalid;
    s_axi_wdata <= s_axi.wdata;
    s_axi_bready <= s_axi.bready;

    uut: entity work.axi2ctrl port map(
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
    
    clk_gen: process
    begin
        aclk <= '0';
        wait for 5ns;
        aclk <= '1';
        wait for 5ns;
    end process clk_gen;
    
    wa <= wr_addr(7 downto 2) & "00";
    ra <= rd_addr(7 downto 2) & "00";
    
    wr: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            regs <= (others => (others => '0'));
        elsif rising_edge(aclk) then
            if wr_en = '1' then
                regs(to_integer(unsigned(wa)) / 4) <= wr_data;
            end if;
        end if;
    end process wr;
    
    rd: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            rd_data <= (others => '0');
        elsif rising_edge(aclk) then
            if rd_en = '1' then
                rd_data <= regs(to_integer(unsigned(ra)) / 4);
            end if;
        end if;
    end process rd;
    
    stimulus: process
        variable i : integer;
        variable data : std_logic_vector(15 downto 0);
    begin
        for i in tb_cycles'range loop
            ar_cycle := tb_cycles(i).ar_cycle;
            r_cycle := tb_cycles(i).r_cycle;
            aw_cycle := tb_cycles(i).aw_cycle;
            w_cycle := tb_cycles(i).w_cycle;
            b_cycle := tb_cycles(i).b_cycle;
            
            aresetn <= '0';
            wait for 10ns;
    
            aresetn <= '1';
            wait for 10ns;
        
            axi_rd(s_axi, X"04", data);
            assert data = X"0000" report "read invalid" severity FAILURE;
            
            axi_rd(s_axi, X"08", data);
            assert data = X"0000" report "read invalid" severity FAILURE;
            
            axi_rd(s_axi, X"0c", data);
            assert data = X"0000" report "read invalid" severity FAILURE;
            
            axi_wr(s_axi, X"04", X"abcd");
            axi_wr(s_axi, X"08", X"ceab");
            
            axi_rd(s_axi, X"04", data);
            assert data = X"abcd" report "read/write invalid" severity FAILURE;
            
            axi_rd(s_axi, X"08", data);
            assert data = X"ceab" report "read/write invalid" severity FAILURE;
            
            axi_rd(s_axi, X"0c", data);
            assert data = X"0000" report "read/write invalid" severity FAILURE;
            
            axi_wr(s_axi, X"08", X"8fff");
            
            axi_rd(s_axi, X"04", data);
            assert data = X"abcd" report "read/write invalid" severity FAILURE;
            
            axi_rd(s_axi, X"08", data);
            assert data = X"8fff" report "read/write invalid" severity FAILURE;
            
            axi_rd(s_axi, X"0c", data);
            assert data = X"0000" report "read/write invalid" severity FAILURE;
            
            axi_rd(s_axi, X"80", data);
            assert data = X"0000" report "read invalid" severity FAILURE;
            
            axi_wr(s_axi, X"80", X"f012");
            
            axi_rd(s_axi, X"80", data);
            assert data = X"f012" report "read/write invalid" severity FAILURE;
            
            axi_rd(s_axi, X"10", data);
            assert data = X"0000" report "read invalid" severity FAILURE;
            
            axi_wr(s_axi, X"10", X"210a");
            
            axi_rd(s_axi, X"10", data);
            assert data = X"210a" report "read/write invalid" severity FAILURE;
            
            axi_rd(s_axi, X"fc", data);
            assert data = X"0000" report "read invalid" severity FAILURE;
            
            axi_wr(s_axi, X"fc", X"1234");
            
            axi_rd(s_axi, X"fc", data);
            assert data = X"1234" report "read invalid" severity FAILURE;
        end loop;
        
        assert false report "Success" severity NOTE;
        
        wait;
    end process stimulus;

end behavioral;
