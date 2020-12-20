library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity auto_vol is
  port(clk  : in std_logic; -- 100MHz
       rst  : in boolean;

       clk_ce_in : in boolean; -- clock enable en entree, 39.0625kHz
       ech_in : in signed(17 downto 0);

       ech_out : out signed(17 downto 0)
      );
end entity;

architecture rtl of auto_vol is

    signal ech_in_reg : signed(17 downto 0);
    signal ech_out_reg : signed(17 downto 0);

    signal gain : signed (24 downto 0);
    signal gain_reg : signed (24 downto 0);
    signal mul_reg : signed (42 downto 0);
    signal max : signed (17 downto 0); -- maximum

    constant n : integer := 64; -- d�cr�mentation du max � chaque coup d'horloge | valeur recomand�e 16
    constant g : integer := 4; -- pas incr�ment/d�cr�ment du gain | valeur recommand�e 4

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
            if (ech_out_reg >= 0) then -- detection du maximum avec ech_out_reg positif
                if (max < ech_out_reg) then
                    max <= ech_out_reg;
                else
                    max <= max - resize ("000000000" & max(17 downto 9),max'length) ; --incr�mentation logarithmique
                end if;
            else -- detection du maximum avec ech_out_reg negatif
                if ( max < (- ech_out_reg)) then
                    max <= (- ech_out_reg);
                else
                    max <= max - resize ("000000000" & max(17 downto 9),max'length); --d�cr�mentation logarithmique
                end if;
            end if;
            
            
            -- calcul gain
            if (max < TO_SIGNED(8000,gain'length)) then
                    gain <= gain + resize ("000000000" & gain(24 downto 9),gain'length) + 1;
                elsif (max > TO_SIGNED(10000,gain'length)) then
                    gain <= gain - resize ("000000000" & gain(24 downto 9),gain'length) - 1;
            end if;
            
            -- 2**18 est �quivalent � un gain de 1
            if (gain < to_signed(2**14,gain_reg'length)) then --saturation n�gative + buffer
                gain_reg <= to_signed(2**14,gain_reg'length);
            elsif (gain > to_signed(2**23,gain_reg'length)) then --saturation positive + buffer
                gain_reg <= to_signed(2**23,gain_reg'length);
            else
                gain_reg <= gain; -- buffer
            end if;
        end if; -- clk_ce_in
        
        mul_reg <= (ech_in_reg * gain_reg);-- application du gain
        ech_out_reg <= resize(mul_reg, 36) (35 downto 18)  ; -- s�lection des bon bits
        
        ech_in_reg <= ech_in; -- bufferisation de l'entree
        ech_out <= ech_out_reg; -- bufferisation de la sortie
        
    end if;--clk
end process;

end architecture;
