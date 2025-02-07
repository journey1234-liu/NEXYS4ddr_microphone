-- GUENEGO Louis
-- ENSEIRB-MATMECA, Electronique 2A, 2020

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity auto_vol is
  port(clk  : in std_logic; -- 100MHz
       rst  : in boolean;

       clk_ce_in : in boolean; -- clock enable input, 39.0625kHz
       ech_in : in signed(17 downto 0);

       ech_out : out signed(17 downto 0)
      );
end entity;

architecture rtl of auto_vol is

    signal ech_in_reg : signed(17 downto 0);
    signal ech_out_reg : signed(17 downto 0);

    signal gain : signed (24 downto 0);
    signal gain_reg : signed (24 downto 0);
    signal gain_reg_reg : signed (24 downto 0);
    signal mul_reg : signed (42 downto 0);
    signal mul_reg_reg : signed (42 downto 0);
    signal max : signed (17 downto 0); -- maximum

    constant n : integer := 64; -- decrement of the max with each clock stroke|  recommended value 16
    constant g : integer := 4; -- not increment/decrement of gain|  recommended value 4

    --  8/4 var 2100 @100Hz
    -- 16/4 var 1000 @100Hz
    -- 32/4 var 700  @100Hz

begin

process (clk)
begin
    if ( rising_edge(clk) ) then
        if (rst) then
            gain <= to_signed(2**18,gain'length);
            max <= to_signed(0,max'length);
            ech_out_reg <= to_signed(0,ech_out_reg'length);
        elsif (clk_ce_in) then
            if (ech_out_reg >= 0) then -- maximum detection with positive ech_out_reg
                if (max < ech_out_reg) then
                    max <= ech_out_reg;
                else
                    max <= max - resize ("000000000" & max(17 downto 9),max'length) ; --logarithmic increment
                end if;
            else -- detection of the maximum with negative ech_out_reg
                if ( max < (- ech_out_reg)) then
                    max <= (- ech_out_reg);
                else
                    max <= max - resize ("000000000" & max(17 downto 9),max'length); --logarithmic decrement
                end if;
            end if;
            
            
            -- calculation gain
            if (max < TO_SIGNED(48000,gain'length)) then
                    gain <= gain + resize ("000000000" & gain(24 downto 9),gain'length) + 1;
                elsif (max > TO_SIGNED(50000,gain'length)) then
                    gain <= gain - resize ("000000000" & gain(24 downto 9),gain'length) - 1;
            end if;
            
            -- 2**18 is equivalent to a gain of 1
            if (gain < to_signed(2**14,gain_reg'length)) then --negative saturation + buffer
                gain_reg <= to_signed(2**14,gain_reg'length);
            elsif (gain > to_signed(2**23,gain_reg'length)) then --positive saturation + buffer
                gain_reg <= to_signed(2**23,gain_reg'length);
            else
                gain_reg <= gain; -- buffer
            end if;
            
            gain_reg_reg <= gain_reg;
            
            mul_reg <= (ech_in_reg * gain_reg_reg);-- application of the gain
            
            mul_reg_reg <= mul_reg;
            
            if ( mul_reg_reg(42 downto 35) > 0 ) then
                ech_out_reg <= to_signed(2**17-1, ech_out_reg'length); -- positive saturation (2**35-1)(35 downto 18)
            elsif ( mul_reg_reg(42 downto 35) < -1 ) then
                ech_out_reg <= to_signed(-2**17, ech_out_reg'length); -- negative saturation (-2**35)(35 downto 18)
            else
                ech_out_reg <= mul_reg_reg(35 downto 18)  ; -- selecting the right bits
            end if;
            
        end if; -- clk_ce_in
        
        ech_in_reg <= ech_in; -- input buffering
        ech_out <= ech_out_reg; -- output buffering
        
    end if;--clk
end process;

end architecture;
