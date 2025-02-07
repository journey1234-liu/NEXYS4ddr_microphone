-- GUENEGO Louis
-- ENSEIRB-MATMECA, Electronique 2A, 2020

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reverb is
generic( t_reverb : integer := 1000 - 2); -- reverberation delay (offset register cut) -- it is better to put a low value for simulations
                                          -- minus 2 because we "lose" 2 steps to calculate
port (
    CLK100MHZ       : in  std_logic;
    CPU_RESETN      : in  boolean;  
    clk_ech : in boolean; -- clock enable, 39062.5Hz
    ech_in      : in  signed(17 downto 0);
    ech_out     : out signed(17 downto 0)
    );
end reverb;

architecture rtl of reverb is

    type t_data_pipe is array (natural range <>) of signed(17  downto 0);
    
    signal p_data       :  t_data_pipe (0 to t_reverb-1) := (others=>to_signed (0, 18));
    
    signal p_ecr : unsigned (14 downto 0);
    signal p_lec : unsigned (14 downto 0);
    
    signal r_add_st1    :  signed(17 downto 0);
    
    signal ech_out_reg    :  signed(18 downto 0); -- larger to not overflow

begin

    p_input : process (CLK100MHZ) -- lag registry management
    begin
        if rising_edge(CLK100MHZ) then
            
            if (clk_ech) then
                p_data(TO_INTEGER(p_ecr)) <= ech_in; -- inserting the new value
                r_add_st1 <= p_data(TO_INTEGER(p_lec)); -- buffer of the sample to be added
                
                if (p_ecr < (t_reverb-2)) then
                    p_ecr <= p_ecr + 1;
                    p_lec <= p_ecr + 2;
                elsif (p_ecr = (t_reverb-2)) then    
                    p_ecr <= p_ecr + 1;
                    p_lec <= to_unsigned (0,p_lec'length);
                elsif (p_ecr = (t_reverb-1)) then
                    p_ecr <= to_unsigned (0,p_ecr'length);
                    p_lec <= to_unsigned (1,p_lec'length);
                end if;
            end if;
                
            if CPU_RESETN then
                --p_data <= (others=>(others=> '0' )); -- do not try to reset on ram!
                r_add_st1 <= to_signed (0, r_add_st1'length);
                p_ecr <= to_unsigned (0,p_ecr'length);
                p_lec <= to_unsigned (1,p_ecr'length);
            end if;
        end if;
    end process p_input;
    
    p_add_st0 : process (CLK100MHZ) -- addition of the recorded sample with the re-entering sample
    begin
        if rising_edge(CLK100MHZ) then
            if CPU_RESETN then
                ech_out_reg <= to_signed (0, ech_out_reg'length);
                ech_out <= to_signed (0, ech_out'length);
                
            elsif (clk_ech) then
            
                ech_out_reg <= resize (ech_in, ech_out_reg'length) + resize (r_add_st1, ech_out_reg'length); -- we lose a step
                
                if ( ech_out_reg >= to_signed(2**17-1,ech_out_reg'length) ) then -- positive saturation -- we lose a second step
                    ech_out <= to_signed(2**17-1,ech_out'length);
                elsif (ech_out_reg <= to_signed(-2**17,ech_out_reg'length)) then -- negative saturation
                    ech_out <= to_signed(-2**17,ech_out'length);
                else -- if no saturation
                    ech_out <= resize(ech_out_reg, ech_out'length);
                end if;
                
            end if;
        end if;
    end process p_add_st0;


end rtl;
