-- GUENEGO Louis
-- ENSEIRB-MATMECA, Electronique 2A, 2020

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity auto_vol_division is
  port(clk  : in std_logic; -- 100MHz
       rst  : in boolean;

       clk_ce_in : in boolean; -- clock enable input, 39.0625kHz
       ech_in : in signed(17 downto 0);

       ech_out : out signed(17 downto 0) := (others => '0')
      );
end entity;

architecture rtl of auto_vol_division is

    signal ech_in_reg : signed(17 downto 0);
    signal ech_out_reg : signed(17 downto 0);

    signal gain : signed (17 downto 0);
    signal gain_buff : signed (17 downto 0);
    signal gain_buff2 : signed (17 downto 0);
    signal gain_moy : signed (17 downto 0);
    signal max : signed (17 downto 0); -- maximum

    constant n : integer := 3; -- decrement of the max with each stroke of the clock

begin

    process (clk)
    begin
      if ( rising_edge(clk) ) then
      
        if (clk_ce_in) then
        
            if (ech_in_reg >= 0) then -- maximum detection
              if (max < ech_in_reg) then
                  max <= ech_in_reg;
              else
                  if (max >= 0) then -- we decrement the max if we do not have superior samples
                    max <= max - n;
                  else
                    max <= max + n;
                  end if;
              end if;
            else
              if (max > ech_in_reg) then
                  max <= ech_in_reg;
              else
                  if (max >= 0) then
                    max <= max - n;
                  else
                    max <= max + n;
                  end if;
              end if;
            end if;
    
            if (clk_ce_in) then
                if (max >= 0) then -- calculation of the gain to be applied
                    gain <=  TO_SIGNED(2**15,gain'length) / max;
                else
                    gain <= TO_SIGNED(2**15,gain'length) / (- max);
                end if;
                gain_buff <= gain ;
            end if;
    
            
            if (gain_buff = 0) then -- gain saturation effect
                gain_buff2 <= to_signed(1* 128, gain_buff2'length) ;
            elsif (gain > 15) then
                gain_buff2 <= to_signed(15* 128, gain_buff'length);
            else
                gain_buff2 <= resize (gain_buff* 128, gain_buff2'length);
            end if;
            
            if (clk_ce_in) then
                if (gain_moy = gain_buff2) then
                    gain_moy <= gain_moy;
                elsif (gain_moy < gain_buff2) then
                    gain_moy <= gain_moy + to_signed(1,gain_moy'length);
                else
                    gain_moy <= gain_moy - to_signed(1,gain_moy'length);
                end if;
            end if;            
    
            ech_out_reg <= resize ((ech_in_reg * gain_moy), 25) (24 downto 7)  ; -- application of the gain
    
    
            ech_in_reg <= ech_in; -- input buffering
            ech_out <= ech_out_reg; -- output buffering
          end if;
      end if;
      
    end process;

end architecture;