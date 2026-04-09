library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_ctrl is
    
end tb_ctrl;

architecture behavioral of tb_ctrl is
    constant REC_CONFIG_REG         : std_logic_vector(7 downto 0) := X"00";
    constant REC_STATUS_REG         : std_logic_vector(7 downto 0) := X"04";
    constant REC_SIZE_REG           : std_logic_vector(7 downto 0) := X"08";
    constant PB_DELAY_MUX_SEL_REG   : std_logic_vector(7 downto 0) := X"0C";
    constant PB_RAMP_GAIN_SEL_REG   : std_logic_vector(7 downto 0) := X"10";
    constant PB_PS_GAIN_SEL_REG     : std_logic_vector(7 downto 0) := X"14";
    constant PB_MIC_GAIN_SEL_REG    : std_logic_vector(7 downto 0) := X"18";
    constant PB_DELAY_GAIN_SEL_REG  : std_logic_vector(7 downto 0) := X"1C";
    constant PB_DELAY_REG           : std_logic_vector(7 downto 0) := X"20";

    signal aclk : std_logic;
    signal aresetn : std_logic;
    
    signal wr_en : std_logic;
    signal wr_addr : std_logic_vector(7 downto 0);
    signal wr_data : std_logic_vector(15 downto 0);
    
    signal rd_en : std_logic;
    signal rd_addr : std_logic_vector(7 downto 0);
    signal rd_data : std_logic_vector(15 downto 0);
    
    signal rec_act : std_logic;
    signal rec_size : std_logic_vector(15 downto 0);
    signal rec_en : std_logic;
    
    signal rec_done : std_logic;
    signal rec_en_status : std_logic;   
    
    signal mclk : std_logic;
    signal mresetn : std_logic;
    
    signal pb_delay_mux_sel : std_logic_vector(1 downto 0);
    
    signal pb_ramp_gain_sel : std_logic_vector(6 downto 0);
    signal pb_ps_gain_sel : std_logic_vector(6 downto 0);
    signal pb_mic_gain_sel : std_logic_vector(6 downto 0);
    signal pb_delay_gain_sel : std_logic_vector(6 downto 0);
    
    signal pb_delay : std_logic_vector(15 downto 0);
    
    procedure wr( signal aclk : in std_logic;
                    signal wr_en : out std_logic;
                    signal wr_addr : out std_logic_vector(7 downto 0);
                    signal wr_data : out std_logic_vector(15 downto 0);
                    addr : in std_logic_vector(7 downto 0);
                    data : in std_logic_vector(15 downto 0) ) is 
    begin
        wait until rising_edge(aclk);
    
        wr_en <= '1';
        wr_addr <= addr;
        wr_data <= data;
        wait until rising_edge(aclk);
        
        wr_en <= '0';
        wait until rising_edge(aclk);
    end procedure;
    
    procedure rd( signal aclk : in std_logic;
                    signal rd_en : out std_logic;
                    signal rd_addr : out std_logic_vector(7 downto 0);
                    signal rd_data : in std_logic_vector(15 downto 0);
                    addr : in std_logic_vector(7 downto 0);
                    data : out std_logic_vector(15 downto 0) ) is 
    begin
        wait until rising_edge(aclk);
    
        rd_en <= '1';
        rd_addr <= addr;
        wait until rising_edge(aclk);
        
        rd_en <= '0';
        wait until rising_edge(aclk);
        
        data := rd_data;
    end procedure;
    
    function vec2str(vec : std_logic_vector) return string is
        variable res : string(0 to ((vec'length / 4) - 1));
        variable j : integer;
        variable k : integer; 
        
        variable cvt : string(0 to 15) := "0123456789abcdef";
    begin
        if vec'ascending then
            j := 0;
        else
            j := vec'length - 1;
        end if;
        
        for i in 0 to ((vec'length/4)  - 1) loop
            if vec'ascending then
                k := to_integer(unsigned(vec(j to j + 3)));
                j := j + 4;
            else
                k := to_integer(unsigned(vec(j downto j - 3)));
                j := j - 4;
            end if;
            res(i) := cvt(k);
        end loop;
        
        return res;
    end vec2str;
    
    signal act : std_logic;
    signal en : std_logic;
    signal done : std_logic;
    signal act_err : std_logic;
    signal en_status : std_logic;
    signal size : std_logic_vector(15 downto 0);
    signal delay_mux_sel : std_logic_vector(1 downto 0);
    signal ramp_gain_sel : std_logic_vector(6 downto 0);
    signal ps_gain_sel : std_logic_vector(6 downto 0);
    signal mic_gain_sel : std_logic_vector(6 downto 0);
    signal delay_gain_sel : std_logic_vector(6 downto 0);
    signal delay : std_logic_vector(15 downto 0);
begin
    uut : entity work.ctrl port map (
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
		
		pb_delay_mux_sel => pb_delay_mux_sel,

		pb_ramp_gain_sel => pb_ramp_gain_sel,
		pb_ps_gain_sel => pb_ps_gain_sel,
		pb_mic_gain_sel => pb_mic_gain_sel,
		pb_delay_gain_sel => pb_delay_gain_sel,
		
		pb_delay => pb_delay
    );
    
    reference_act: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            act <= '0';
            done <= '0';
            act_err <= '0';
        elsif rising_edge(aclk) then
            if act = '0' then
                if (wr_en = '1') and (wr_addr = REC_CONFIG_REG) and (wr_data(0) = '1') then
                    act <= '1';
                    
                    done <= '0';
                    act_err <= '0';
                end if;
            else
                if (wr_en = '1') and (wr_addr = REC_CONFIG_REG) and (wr_data(0) = '1') then
                    act_err <= '1';
                end if;
            
                if rec_done = '1' then
                    act <= '0';
                    done <= '1';
                end if;
            end if;
        end if;
    end process reference_act;
    
    reference_en: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            en <= '0';
        elsif rising_edge(aclk) then
            if (wr_en = '1') and (wr_addr = REC_CONFIG_REG) and (wr_data(1) = '1') then
                en <= not en;
            end if;
        end if;
    end process reference_en;
    
    reference_en_status: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            en_status <= '0';
        elsif rising_edge(aclk) then
            en_status <= rec_en;
        end if;
    end process reference_en_status;
    
    rec_en_status <= en_status;
    
    reference_size: process(aclk, aresetn)
    begin
        if aresetn = '0' then
            size <= (others => '0');
        elsif rising_edge(aclk) then
            if (wr_en = '1') and (wr_addr = REC_SIZE_REG) then
                size <= wr_data;
            end if;
        end if;
    end process reference_size;
    
    reference_pb_reg: process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                delay_mux_sel <= "00";
                ramp_gain_sel <= "0000000";
                ps_gain_sel <= "0000000";
                mic_gain_sel <= "1110011";
                delay_gain_sel <= "0000000";
                delay <= (others => '0');
            else
                if (wr_en = '1') and (wr_addr = PB_DELAY_MUX_SEL_REG) then
                    delay_mux_sel <= wr_data(1 downto 0);
                end if;
                
                if (wr_en = '1') and (wr_addr = PB_RAMP_GAIN_SEL_REG) then
                    ramp_gain_sel <= wr_data(6 downto 0);
                end if;
                
                if (wr_en = '1') and (wr_addr = PB_PS_GAIN_SEL_REG) then
                    ps_gain_sel <= wr_data(6 downto 0);
                end if;
                
                if (wr_en = '1') and (wr_addr = PB_MIC_GAIN_SEL_REG) then
                    mic_gain_sel <= wr_data(6 downto 0);
                end if;
                
                if (wr_en = '1') and (wr_addr = PB_DELAY_GAIN_SEL_REG) then
                    delay_gain_sel <= wr_data(6 downto 0);
                end if;
                
                if (wr_en = '1') and (wr_addr = PB_DELAY_REG) then
                    delay <= wr_data(15 downto 0);
                end if;
            end if;
        end if;
    end process reference_pb_reg;
    
    reference_read: process(aclk, aresetn)
        variable next_valid : boolean;
        variable next_addr : std_logic_vector(7 downto 0);
        variable next_data : std_logic_vector(15 downto 0);
    begin
        if aresetn = '0' then
            next_valid := false;
        elsif rising_edge(aclk) then
            assert rec_act = act report "invalid rec_act" severity FAILURE;
            assert rec_en = en report "invalid rec_en" severity FAILURE;
            assert rec_size = size report "invalid rec_size" severity FAILURE;
        
            if next_valid then
                report "check read data @ " & vec2str(next_addr) & " = " & vec2str(next_data) severity NOTE;
                assert rd_data = next_data report "invalid read data" severity FAILURE;
                next_valid := false;
            end if;
            
            if rd_en = '1' then
                next_valid := true;
                next_addr := rd_addr;
            
                if rd_addr = REC_CONFIG_REG then
                    next_data := "00000000000000" & en & act;
                end if;    
                
                if rd_addr = REC_STATUS_REG then
                    next_data := "0000000000000" & en_status & act_err & done;
                end if;
                
                if rd_addr = REC_SIZE_REG then
                    next_data := size;
                end if;
                
                if rd_addr = PB_DELAY_MUX_SEL_REG then
                    next_data := "00000000000000" & delay_mux_sel; 
                end if;
                
                if rd_addr = PB_RAMP_GAIN_SEL_REG then
                    next_data := "000000000" & ramp_gain_sel;
                end if;
                
                if rd_addr = PB_PS_GAIN_SEL_REG then
                    next_data := "000000000" & ps_gain_sel;
                end if;
                
                if rd_addr = PB_MIC_GAIN_SEL_REG then
                    next_data := "000000000" & mic_gain_sel;
                end if;
                
                if rd_addr = PB_DELAY_GAIN_SEL_REG then
                    next_data := "000000000" & delay_gain_sel;
                end if;
                
                if rd_addr = PB_DELAY_REG then
                    next_data := delay;
                end if;
            end if;
        end if;
    end process reference_read;
    
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
    
    stimulus: process
        variable i : integer;
        variable data : std_logic_vector(15 downto 0);
    begin
        wr_en <= '0';
        rd_en <= '0';
        rec_done <= '0';
    
        aresetn <= '0';
        mresetn <= '0';
        wait for 200ns;

        aresetn <= '1';
        wait until rising_edge(aclk);
        
        mresetn <= '1';
        wait until rising_edge(mclk);
        
        -- write config, activate
        wr(aclk, wr_en, wr_addr, wr_data, REC_CONFIG_REG, X"0001");
        
        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
        
        -- write config again, enable
        wr(aclk, wr_en, wr_addr, wr_data, REC_CONFIG_REG, X"0002");
        
        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
        
        -- write size
        wr(aclk, wr_en, wr_addr, wr_data, REC_SIZE_REG, X"0200");
        
        -- check size
        rd(aclk, rd_en, rd_addr, rd_data, REC_SIZE_REG, data);
        
        -- signal done
        assert rec_act = '1' report "invalid rec_act" severity FAILURE; 
        
        rec_done <= '1';
        wait until rising_edge(aclk) and rec_act = '0';
        
        rec_done <= '0';
        
        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        assert data = X"0002" report "invalid config" severity FAILURE;
        
        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
        assert data = X"0005" report "invalid status" severity FAILURE;
        
        -- write config, activate
        wr(aclk, wr_en, wr_addr, wr_data, REC_CONFIG_REG, X"0001");
        
        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
        
        -- write config, try to deactivate
        wr(aclk, wr_en, wr_addr, wr_data, REC_CONFIG_REG, X"0001");
        
        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        assert data = X"0003" report "invalid config" severity FAILURE;

        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
        assert data = X"0006" report "invalid status" severity FAILURE;
        
        -- signal done
        rec_done <= '1';
        wait until rising_edge(aclk) and rec_act = '0';

        rec_done <= '0';
        
        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        assert data = X"0002" report "invalid config" severity FAILURE;

        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
        assert data = X"0007" report "invalid status" severity FAILURE;
        
        -- write config, activate
        wr(aclk, wr_en, wr_addr, wr_data, REC_CONFIG_REG, X"0001");
        
        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        assert data = X"0003" report "invalid config" severity FAILURE;

        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
        assert data = X"0004" report "invalid status" severity FAILURE;
        
        -- write config, disable
        wr(aclk, wr_en, wr_addr, wr_data, REC_CONFIG_REG, X"0002");
        
        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
                
        -- write config, enable
        wr(aclk, wr_en, wr_addr, wr_data, REC_CONFIG_REG, X"0002");

        -- check config and status
        rd(aclk, rd_en, rd_addr, rd_data, REC_CONFIG_REG, data);
        rd(aclk, rd_en, rd_addr, rd_data, REC_STATUS_REG, data);
        
        -- test pb_delay_mux_sel
        wait until rising_edge(mclk);
        assert pb_delay_mux_sel = "00" report "pb_delay_mux_sel default invalid" severity FAILURE;
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_DELAY_MUX_SEL_REG, data);
        assert data = X"0000" report "pb_delay_mux_sel register data invalid" severity FAILURE;
        
        -- write pb_delay_mux_sel
        wr(aclk, wr_en, wr_addr, wr_data, PB_DELAY_MUX_SEL_REG, X"0001");
        
        -- check pb_delay_mux_sel register value
        rd(aclk, rd_en, rd_addr, rd_data, PB_DELAY_MUX_SEL_REG, data);
        assert data = X"0001" report "invalid pb_delay_mux_sel register data" severity FAILURE; 
        
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        
        assert pb_delay_mux_sel = "01" report "invalid pb_delay_mux_sel" severity FAILURE;
        
        -- write pb_delay_mux_sel with another value
        wr(aclk, wr_en, wr_addr, wr_data, PB_DELAY_MUX_SEL_REG, X"0002");
        
        -- check pb_delay_mux_sel register value
        rd(aclk, rd_en, rd_addr, rd_data, PB_DELAY_MUX_SEL_REG, data);
        assert data = X"0002" report "invalid pb_delay_mux_sel register data" severity FAILURE; 
        
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        
        assert pb_delay_mux_sel = "10" report "invalid pb_delay_mux_sel" severity FAILURE;
        
        -- test pb_[ramp|ps|mic|delay]_gain_sel
        rd(aclk, rd_en, rd_addr, rd_data, PB_RAMP_GAIN_SEL_REG, data);
        assert data = X"0000" report "invalid pb_ramp_gain_sel register default data" severity FAILURE;
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_PS_GAIN_SEL_REG, data);
        assert data = X"0000" report "invalid pb_ps_gain_sel register default data" severity FAILURE;
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_MIC_GAIN_SEL_REG, data);
        assert data = X"0073" report "invalid pb_mic_gain_sel register default data" severity FAILURE;
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_DELAY_GAIN_SEL_REG, data);
        assert data = X"0000" report "invalid pb_delay_gain_sel register default data" severity FAILURE;
        
        assert pb_ramp_gain_sel = "0000000" report "invalid pb_ramp_gain_sel" severity FAILURE;
        assert pb_ps_gain_sel = "0000000" report "invalid pb_ps_gain_sel" severity FAILURE;
        assert pb_mic_gain_sel = "1110011" report "invalid pb_mic_gain_sel" severity FAILURE;
        assert pb_delay_gain_sel = "0000000" report "invalid pb_delay_gain_sel" severity FAILURE;
        
        wr(aclk, wr_en, wr_addr, wr_data, PB_RAMP_GAIN_SEL_REG, X"0070");
        wr(aclk, wr_en, wr_addr, wr_data, PB_PS_GAIN_SEL_REG, X"0060");
        wr(aclk, wr_en, wr_addr, wr_data, PB_MIC_GAIN_SEL_REG, X"007f");
        wr(aclk, wr_en, wr_addr, wr_data, PB_DELAY_GAIN_SEL_REG, X"003f");
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_RAMP_GAIN_SEL_REG, data);
        assert data = X"0070" report "invalid pb_ramp_gain_sel register data" severity FAILURE;
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_PS_GAIN_SEL_REG, data);
        assert data = X"0060" report "invalid pb_ps_gain_sel register data" severity FAILURE;
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_MIC_GAIN_SEL_REG, data);
        assert data = X"007f" report "invalid pb_mic_gain_sel register data" severity FAILURE;
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_DELAY_GAIN_SEL_REG, data);
        assert data = X"003f" report "invalid pb_delay_gain_sel register data" severity FAILURE;
        
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        
        assert pb_ramp_gain_sel = "1110000" report "invalid pb_ramp_gain_sel" severity FAILURE;
        assert pb_ps_gain_sel = "1100000" report "invalid pb_ps_gain_sel" severity FAILURE;
        assert pb_mic_gain_sel = "1111111" report "invalid pb_mic_gain_sel" severity FAILURE;
        assert pb_delay_gain_sel = "0111111" report "invalid pb_delay_gain_sel" severity FAILURE;
        
        -- test mic_gain_sel set to a mute value
        wr(aclk, wr_en, wr_addr, wr_data, PB_MIC_GAIN_SEL_REG, X"0027");
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_MIC_GAIN_SEL_REG, data);
        assert data = X"0027" report "invalid pb_mic_gain_sel register data" severity FAILURE;
        
        -- test writing unused bits
        wr(aclk, wr_en, wr_addr, wr_data, PB_PS_GAIN_SEL_REG, X"00ff");
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_PS_GAIN_SEL_REG, data);
        assert data = X"007f" report "invalid pb_ps_gain_sel register data" severity FAILURE;
        
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        
        assert pb_ramp_gain_sel = "1110000" report "invalid pb_ramp_gain_sel" severity FAILURE;
        assert pb_ps_gain_sel = "1111111" report "invalid pb_ps_gain_sel" severity FAILURE;
        assert pb_mic_gain_sel = "0100111" report "invalid pb_mic_gain_sel" severity FAILURE;
        assert pb_delay_gain_sel = "0111111" report "invalid pb_delay_gain_sel" severity FAILURE;
        
        -- test pb_delay register
        rd(aclk, rd_en, rd_addr, rd_data, PB_DELAY_REG, data);
        assert data = X"0000" report "invalid pb_delay register default data" severity FAILURE;
        
        assert pb_delay = X"0000" report "invalid pb_delay" severity FAILURE;
        
        wr(aclk, wr_en, wr_addr, wr_data, PB_DELAY_REG, X"123a");
        
        rd(aclk, rd_en, rd_addr, rd_data, PB_DELAY_REG, data);
        assert data = X"123a" report "invalid pb_delay register data" severity FAILURE;
        
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);
        
        assert pb_delay = X"123a" report "invalid pb_delay" severity FAILURE;

        assert false report "Success" severity NOTE;
        
        wait;
    end process stimulus;
end behavioral;
