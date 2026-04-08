-- Copyright (c) 2026 Bogdan Petrica
-- SPDX-License-Identifier: Apache-2.0
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity core is
    port (
        signal mclk : in std_logic;
        signal mresetn : in std_logic;
        
        signal ramp_gain_sel : std_logic_vector(6 downto 0);
        signal ps_gain_sel : std_logic_vector(6 downto 0);
        signal mic_gain_sel : std_logic_vector(6 downto 0);
        signal delay_gain_sel : std_logic_vector(6 downto 0);
            
        signal sstb_out : out std_logic;
        signal ramp_in : in std_logic_vector(63 downto 0);
        signal ps_in : in std_logic_vector(63 downto 0);
        signal mic_in : in std_logic_vector(63 downto 0);
        signal delay_in : in std_logic_vector(63 downto 0);
        
        signal sstb_in : in std_logic;
        signal data_out : out std_logic_vector(63 downto 0)
    );
end core;

architecture behavioral of core is
    constant GAIN_FRACTION_WIDTH : integer := 13;
    constant WIDTH : integer := 43;
    
    signal rom_da : std_logic_vector(15 downto 0);
    signal rom_db : std_logic_vector(15 downto 0);
    signal rom_dc : std_logic_vector(15 downto 0);
    signal rom_dd : std_logic_vector(15 downto 0);

    -- stage 1 signals and registers
    signal a_gain : signed(15 downto 0);
    signal b_gain : signed(15 downto 0);
    signal c_gain : signed(15 downto 0);
    signal d_gain : signed(15 downto 0);
    
    signal a_l : signed(15 downto 0);
    signal a_r : signed(15 downto 0);
    signal b_l : signed(15 downto 0);
    signal b_r : signed(15 downto 0);
    signal c_l : signed(15 downto 0);
    signal c_r : signed(15 downto 0);
    signal d_l : signed(15 downto 0);
    signal d_r : signed(15 downto 0);
    
    -- stage 2 registers
    signal a_l_prod : signed(WIDTH - 1 downto 0);
    signal a_r_prod : signed(WIDTH - 1 downto 0);
    
    signal b_l_prod : signed(WIDTH - 1 downto 0);
    signal b_r_prod : signed(WIDTH - 1 downto 0);
    
    signal c_gain_d : signed(15 downto 0);
    signal d_gain_d : signed(15 downto 0);
    
    signal c_l_d : signed(15 downto 0);
    signal c_r_d : signed(15 downto 0);
    signal d_l_d : signed(15 downto 0);
    signal d_r_d : signed(15 downto 0);
    
    -- stage 3 registers
    signal b_l_sum : signed(WIDTH - 1 downto 0); 
    signal b_r_sum : signed(WIDTH - 1 downto 0);
    
    signal c_l_prod : signed(WIDTH - 1 downto 0);
    signal c_r_prod : signed(WIDTH - 1 downto 0);
    
    signal d_gain_dd : signed(15 downto 0);
    
    signal d_l_dd : signed(15 downto 0);
    signal d_r_dd : signed(15 downto 0);
    
    -- stage 4 registers
    signal c_l_sum : signed(WIDTH - 1 downto 0);
    signal c_r_sum : signed(WIDTH - 1 downto 0);
    
    signal d_l_prod : signed(WIDTH - 1 downto 0);
    signal d_r_prod : signed(WIDTH - 1 downto 0);
    
    -- stage 5 registers
    signal d_l_sum : signed(WIDTH - 1 downto 0);
    signal d_r_sum : signed(WIDTH - 1 downto 0);
    
    signal final_l_sum : signed(WIDTH - GAIN_FRACTION_WIDTH - 1 downto 0);
    signal final_r_sum : signed(WIDTH - GAIN_FRACTION_WIDTH - 1 downto 0);
    
    -- last stage register
    signal result_l : std_logic_vector(15 downto 0);
    signal result_r : std_logic_vector(15 downto 0);
    
    -- result must fit into 16 signed integer, do overflow detection on all msb bits
    function apply_saturation(value : signed) return std_logic_vector is
        constant ZEROS : signed(value'length - 1 downto 15) := (others => '0');
        constant ONES : signed(value'length - 1 downto 15) := (others => '1');
        
        constant INTEGRAL : signed(value'length - 1 downto 15) := value(value'length - 1 downto 15);

        variable overflow : boolean;
    begin
        overflow := not((INTEGRAL = ZEROS) or (INTEGRAL = ONES));
            
        if overflow then
            if value(value'length - 1) = '0' then
                return std_logic_vector(to_signed(32767, 16));
            else
                return std_logic_vector(to_signed(-32768, 16));
            end if;
        else  
            return std_logic_vector(value(15 downto 0));
        end if; 
    end function apply_saturation;
begin
    sstb_out <= sstb_in;

    rom_inst : entity work.gain_rom port map (
        aclk => mclk,
        rden => '1',
        
        a => ramp_gain_sel,
        b => ps_gain_sel,
        c => mic_gain_sel,
        d => delay_gain_sel,
        
        da => rom_da,
        db => rom_db,
        dc => rom_dc,
        dd => rom_dd
    );
    
    -- pipe stage 1 - gain factors are already delayed by one cycle
    a_gain <= signed(rom_da);
    b_gain <= signed(rom_db);
    c_gain <= signed(rom_dc);
    d_gain <= signed(rom_dd);
    
    -- pipe stage 1 - load sample values
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                a_l <= (others => '0');
                a_r <= (others => '0');
                
                b_l <= (others => '0');
                b_r <= (others => '0');
                
                c_l <= (others => '0');
                c_r <= (others => '0');
                
                d_l <= (others => '0');
                d_r <= (others => '0');
            else
                if sstb_in = '1' then
                    a_l <= signed(ramp_in(63 downto 48));
                    a_r <= signed(ramp_in(31 downto 16));
                    
                    b_l <= signed(ps_in(63 downto 48));
                    b_r <= signed(ps_in(31 downto 16));
                    
                    c_l <= signed(mic_in(63 downto 48));
                    c_r <= signed(mic_in(31 downto 16));
                    
                    d_l <= signed(delay_in(63 downto 48));
                    d_r <= signed(delay_in(31 downto 16));
                end if;
            end if;
        end if;
    end process;
    
    -- pipe stage 2
    --      a_[lr]_prod <= a_[lr] x a_gain
    --      b_[lr]_prod <= b_[lr] x b_gain
    --      c_gain_d <= c_gain
    --      d_gain_d <= d_gain 
    --      c_[lr]_d <= c_[lr]
    --      d_[lr]_d <= d_[lr]
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                a_l_prod <= (others => '0');
                a_r_prod <= (others => '0');
                
                b_l_prod <= (others => '0');
                b_r_prod <= (others => '0');
                
                c_gain_d <= (others => '0');
                d_gain_d <= (others => '0');
                
                c_l_d <= (others => '0');
                c_r_d <= (others => '0');
                
                d_l_d <= (others => '0');
                d_r_d <= (others => '0');
            else
                if sstb_in = '1' then
                    a_l_prod <= resize(a_l * a_gain, WIDTH);
                    a_r_prod <= resize(a_r * a_gain, WIDTH);
                    
                    b_l_prod <= resize(b_l * b_gain, WIDTH);
                    b_r_prod <= resize(b_r * b_gain, WIDTH);
                    
                    c_gain_d <= c_gain;
                    d_gain_d <= d_gain;
                    
                    c_l_d <= c_l;
                    c_r_d <= c_r;
                    
                    d_l_d <= d_l;
                    d_r_d <= d_r;
                end if;
            end if;
        end if;
    end process;
    
    -- pipe stage 3
    --      b_[lr]_sum = a_[lr]_prod + b_[lr]_prod
    --      c_[lr]_prod = c_[lr]_d * c_gain_d
    --      d_gain_dd <= d_gain_d 
    --      d_[lr]_dd <= d_[lr]_d
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                b_l_sum <= (others => '0');
                b_r_sum <= (others => '0');
                
                c_l_prod <= (others => '0');
                c_r_prod <= (others => '0');
                
                d_gain_dd <= (others => '0');
                
                d_l_dd <= (others => '0');
                d_r_dd <= (others => '0');
            else
                if sstb_in = '1' then
                    b_l_sum <= a_l_prod + b_l_prod;
                    b_r_sum <= a_r_prod + b_r_prod;
                    
                    c_l_prod <= resize(c_l_d * c_gain_d, WIDTH);
                    c_r_prod <= resize(c_r_d * c_gain_d, WIDTH);
                    
                    d_gain_dd <= d_gain_d;
                    
                    d_l_dd <= d_l_d;
                    d_r_dd <= d_r_d;
                end if; 
            end if;
        end if;
    end process;
    
    -- pipe stage 4
    --      c_[lr]_sum = b_[lr]_sum + c_[lr]_prod
    --      d_[lr]_prod = d_[lr]_dd * d_gain_dd
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                c_l_sum <= (others => '0');
                c_r_sum <= (others => '0');
                
                d_l_prod <= (others => '0');
                d_r_prod <= (others => '0');
            else
                if sstb_in = '1' then
                    c_l_sum <= b_l_sum + c_l_prod;
                    c_r_sum <= b_r_sum + c_r_prod;
                    
                    d_l_prod <= resize(d_l_dd * d_gain_dd, WIDTH);
                    d_r_prod <= resize(d_r_dd * d_gain_dd, WIDTH);
                end if;
            end if; 
        end if;
    end process;
    
    -- pipe stage 5
    --      d_[lr]_sum = c_[lr]_sum + d_[lr]_prod
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                d_l_sum <= (others => '0');
                d_r_sum <= (others => '0');
            else
                if sstb_in = '1' then
                    d_l_sum <= c_l_sum + d_l_prod;
                    d_r_sum <= c_r_sum + d_r_prod;
                end if;
            end if;
        end if;
    end process;
    
    final_l_sum <= d_l_sum(WIDTH - 1 downto GAIN_FRACTION_WIDTH);
    final_r_sum <= d_r_sum(WIDTH - 1 downto GAIN_FRACTION_WIDTH);
    
    -- last stage - generate the result
    process(mclk)
    begin
        if rising_edge(mclk) then
            if mresetn = '0' then
                result_l <= (others => '0');
                result_r <= (others => '0');
            else
                if sstb_in = '1' then
                    result_l <= apply_saturation(final_l_sum);
                    result_r <= apply_saturation(final_r_sum);
                end if;
            end if;
        end if;
    end process;
    
    data_out <= result_l & X"0000" & result_r & X"0000";
end behavioral;
