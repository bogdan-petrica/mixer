-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.math_real.all;

entity tb_core is
end tb_core;

architecture behavioral of tb_core is
    constant GAIN_FRACTION_WIDTH : integer := 13;
    constant DB_MIN : real := -34.0;
    constant DB_MAX : real := 6.0;
    constant DB_STEP : real := 0.5;
    constant DB_MAX_LEVEL : integer := 127;

    signal mclk : std_logic;
    signal mresetn : std_logic;
    
    signal ramp_gain_sel : std_logic_vector(6 downto 0);
    signal ps_gain_sel : std_logic_vector(6 downto 0);
    signal mic_gain_sel : std_logic_vector(6 downto 0);
    signal delay_gain_sel : std_logic_vector(6 downto 0);
    
    signal sstb_in : std_logic;
    signal ramp_out : std_logic_vector(63 downto 0);
    signal ps_out : std_logic_vector(63 downto 0);
    signal mic_out : std_logic_vector(63 downto 0);
    signal delay_out : std_logic_vector(63 downto 0);
    
    signal sstb_out : std_logic;
    signal data_in : std_logic_vector(63 downto 0);
    
    function gain_sel(db : real) return std_logic_vector is
    begin
        assert db <= DB_MAX report "precondition" severity FAILURE;
        assert db mod DB_STEP = 0.0 report "precondition" severity FAILURE;
        
        if db < DB_MIN then
            return std_logic_vector(to_unsigned(46, 7));
        end if;
        
        return std_logic_vector(to_unsigned(DB_MAX_LEVEL + integer((db - DB_MAX) / DB_STEP), 7));
    end function gain_sel;
    
    function db2int(db : real) return real is
    begin
        assert db <= DB_MAX report "precondition" severity FAILURE;
        assert db mod DB_STEP = 0.0 report "precondition" severity FAILURE;
    
        if db < DB_MIN then
            return 0.0;
        else
            return exp(db / 10.0 * log(10.0));
        end if;
    end function db2int;
    
    function sel2db(sel : std_logic_vector(6 downto 0)) return real is
        variable l : integer;
        variable db : real;
    begin
        l := to_integer(unsigned(sel));
        assert l <= DB_MAX_LEVEL report "precondition" severity FAILURE;
        db := DB_MAX - real(DB_MAX_LEVEL - l) * DB_STEP;
        return db;
    end function sel2db;
    
    type SAMPLE is record
        a, b, c, d: integer; 
    end record;
    
    type GAIN_FACTORS is record
        x, y, z, w : real;
    end record;
    
    procedure get_expected(s : in SAMPLE;
        g : in GAIN_FACTORS;
        expected : out integer;
        max_err : out integer) is
        
        variable value : integer;     
        
        constant err_factor : real := 2.0 ** real(-GAIN_FRACTION_WIDTH);
    begin
        value:= integer(
            floor(
                real(s.a) * db2int(g.x) +
                real(s.b) * db2int(g.y) +
                real(s.c) * db2int(g.z) +
                real(s.d) * db2int(g.w)));

        if value > 32767 then
            expected := 32767;
            max_err := 0;
        elsif value < -32768 then
            expected := -32768;
            max_err := 0;
        else
            expected := value;
            max_err := integer(
                ceil(abs(real(s.a) * err_factor)) +
                ceil(abs(real(s.b) * err_factor)) +
                ceil(abs(real(s.c) * err_factor)) +
                ceil(abs(real(s.d) * err_factor)));
        end if;
    end procedure get_expected;
    
    type TEST_VECTOR is record
        s : SAMPLE;
        g : GAIN_FACTORS;
    end record;
    
    type TEST_VECTOR_ARR is array(natural range <>) of TEST_VECTOR;
   
    type TEST_VECTOR_HISTORY is record
        l, r : SAMPLE;
        g : GAIN_FACTORS;
    end record;
    
    type TEST_VECTOR_HISTORY_ARR is array(natural range <>) of TEST_VECTOR_HISTORY;
    
    signal history : TEST_VECTOR_HISTORY_ARR(0 to 5) := (others => ((others => 0), (others => 0), (others => 0.0))); 
    
    constant test_vectors : TEST_VECTOR_ARR :=
	(
		-- test cases with d zero
        ((+30000,  +3000,    -234,     +0), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        (( +3000, +30000,    -233,     +0), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        ((+28000,  +5000,    -232,     +0), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        ((+28000,  +5000,   -1000,     +0), (   +0.0,  +0.0,  +0.0,  +0.0 )),
									 
        ((-30000,  -3000,    +232,     +0), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        (( -3000, -30000,    +233,     +0), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        ((-28000,  -5000,    +231,     +0), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        ((-28000,  -5000,   +1000,     +0), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        
        -- test cases with b zero
        (( +30000,    +0,  +3000,    -234), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        ((  +3000,    +0, +30000,    -233), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        (( +28000,    +0,  +5000,    -232), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        (( +28000,    +0,  +5000,   -1000), (   +0.0,  +0.0,  +0.0,  +0.0 )),
					
        (( -30000,    +0,  -3000,    +232), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        ((  -3000,    +0, -30000,    +233), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        (( -28000,    +0,  -5000,    +231), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        (( -28000,    +0,  -5000,   +1000), (   +0.0,  +0.0,  +0.0,  +0.0 )),
        
        ((+32767, +32767,  +32767, +32767), (   +6.0,  +6.0,  +6.0,  +6.0 )),
        ((-32768, -32768,  -32768, -32768), (   +6.0,  +6.0,  +6.0,  +6.0 )),
									 
        (( +3000,  -2000,    +500,   -800), (   +3.0,  +3.0,  +3.0,  +3.0 )),
        (( +3000,  -2000,    +500,   -800), (   -7.0,  -7.0,  -7.0,  -7.0 )),
									 
        ((+10000,  -1000,   -3000,  +3000), (   -2.5,  +4.0,  +2.5,  -0.5 )),
									 
        ((+32767, +32767, +32767,  +32767), (  -34.0, -34.0, -34.0, -34.0 )),
        ((-32768, -32768, -32768,  -32768), (  -34.0, -34.0, -34.0, -34.0 )),
									 
        ((+32767, +32767, +32767,  +32767), (  -60.0, -60.0, -60.0, -60.0 )),
        ((-32768, -32768, -32768,  -32768), (  -60.0, -60.0, -60.0, -60.0 )),
									 
        (( +1000,  +2000,  +3000,   -2000), (   +6.0,  +6.0,  +6.0,  +6.0 )),
        (( -1000,  -2000,  -3000,   +2000), (   +6.0,  +6.0,  +6.0,  +6.0 ))
    );
    
    signal verify_stop : boolean := false;
   
        
begin

    uut: entity work.core port map (
        mclk => mclk,
        mresetn => mresetn,
        
        ramp_gain_sel => ramp_gain_sel,
        ps_gain_sel => ps_gain_sel,
        mic_gain_sel => mic_gain_sel,
        delay_gain_sel => delay_gain_sel,
        
        sstb_out => sstb_in,
        ramp_in => ramp_out,
        ps_in => ps_out,
        mic_in => mic_out,
        delay_in => delay_out,
        
        sstb_in => sstb_out,
        data_out => data_in
    );
    
    mclk_gen: process
    begin
        mclk <= '0';
        wait for 40.69ns;
        mclk <= '1';
        wait for 40.69ns;
    end process mclk_gen;
    
    verify: process
        variable left_out : integer;
        variable right_out : integer;
        
        variable left_expected : integer;
        variable right_expected : integer;
        
        variable left_max_err : integer;
        variable right_max_err : integer;
        
        variable h : TEST_VECTOR_HISTORY;
        
        variable i : integer;
    begin
        loop
            wait until rising_edge(mclk);
            
            if verify_stop then
                exit;
            end if;
            
            if sstb_out = '1' then            
                left_out := to_integer(signed(data_in(63 downto 48)));
                right_out := to_integer(signed(data_in(31 downto 16)));
                
                h := history(0);        
                
                get_expected(h.l, h.g, left_expected, left_max_err);
                get_expected(h.r, h.g, right_expected, right_max_err); 
                
                report "test case a: " & integer'image(h.l.a) &
                        ", b: " & integer'image(h.l.b) &
                        ", c: " & integer'image(h.l.c) &
                        ", d: " & integer'image(h.l.d) &
                        ", a_gain: " & real'image(h.g.x) &
                        ", b_gain: " & real'image(h.g.y) &
                        ", c_gain: " & real'image(h.g.z) &
                        ", d_gain: " & real'image(h.g.w) &
                        ", expected: " & integer'image(left_expected) &
                        ", out: " & integer'image(left_out) &
                        ", max_err: " & integer'image(left_max_err);
                
                assert abs(left_out - left_expected) <= left_max_err report "error on left channel" severity FAILURE;
                assert abs(right_out - right_expected) <= right_max_err report "error on left channel" severity FAILURE;
                
                for i in 1 to history'high loop
                    history(i-1) <= history(i);
                end loop;
                
                h.l.a := to_integer(signed(ramp_out(63 downto 48)));
                h.l.b := to_integer(signed(ps_out(63 downto 48)));
                h.l.c := to_integer(signed(mic_out(63 downto 48)));
                h.l.d := to_integer(signed(delay_out(63 downto 48))); 
                
                h.r.a := to_integer(signed(ramp_out(31 downto 16)));
                h.r.b := to_integer(signed(ps_out(31 downto 16)));
                h.r.c := to_integer(signed(mic_out(31 downto 16)));
                h.r.d := to_integer(signed(delay_out(31 downto 16)));
                
                h.g.x := sel2db(ramp_gain_sel);
                h.g.y := sel2db(ps_gain_sel);
                h.g.z := sel2db(mic_gain_sel);
                h.g.w := sel2db(delay_gain_sel);
                
                history(history'high) <= h;
            end if;
        end loop;
        
        wait;
    end process;
    
    stimulus: process
        variable i : integer;
        
        variable ramp_left, ramp_right : std_logic_vector(15 downto 0);
        variable ps_left, ps_right : std_logic_vector(15 downto 0);
        variable mic_left, mic_right : std_logic_vector(15 downto 0);
        variable delay_left, delay_right : std_logic_vector(15 downto 0);
        
        variable seed1 : integer := 1;
        variable seed2 : integer := 1;
        variable rand : real;
        variable rand_int : integer;

    begin
        wait until rising_edge(mclk);
        mresetn <= '0';
        
        for i in 0 to 7 loop
            wait until rising_edge(mclk);
        end loop;
        
        mresetn <= '1';
        wait until rising_edge(mclk);
        
        for i in 0 to test_vectors'length - 1 loop
            sstb_out <= '1';
        
            ramp_left := std_logic_vector(to_signed(test_vectors(i).s.a, 16));
            ps_left := std_logic_vector(to_signed(test_vectors(i).s.b, 16));
            mic_left := std_logic_vector(to_signed(test_vectors(i).s.c, 16));
            delay_left := std_logic_vector(to_signed(test_vectors(i).s.d, 16));
            
            ramp_right := std_logic_vector(to_signed(test_vectors(i).s.b, 16));
            ps_right := std_logic_vector(to_signed(test_vectors(i).s.c, 16));
            mic_right := std_logic_vector(to_signed(test_vectors(i).s.d, 16));
            delay_right := std_logic_vector(to_signed(test_vectors(i).s.a, 16));
            
            ramp_out <= ramp_left & X"0000" & ramp_right & X"0000";
            ps_out <= ps_left & X"0000" & ps_right & X"0000";
            mic_out <= mic_left & X"0000" & mic_right & X"0000";
            delay_out <= delay_left & X"0000" & delay_right & X"0000";
            
            ramp_gain_sel <= gain_sel(test_vectors(i).g.x);
            ps_gain_sel <= gain_sel(test_vectors(i).g.y);
            mic_gain_sel <= gain_sel(test_vectors(i).g.z);
            delay_gain_sel <= gain_sel(test_vectors(i).g.w);
            
            wait until rising_edge(mclk);
            
            uniform(seed1, seed2, rand);
            rand_int := integer(round(rand * 3.0)) mod 3;
            if rand_int > 0 then
                sstb_out <= '0';
                for i in 0 to rand_int - 1 loop
                    wait until rising_edge(mclk);
                end loop;
            end if;
        end loop;
        
        sstb_out <= '1';
        for i in 0 to 15 loop
            wait until rising_edge(mclk);
        end loop;
        
        verify_stop <= true;
        wait until rising_edge(mclk);
        
        assert false report "success" severity NOTE;
        
        wait;
    end process stimulus;
end behavioral;
