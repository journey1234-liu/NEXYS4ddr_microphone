-- GUENEGO Louis
-- ENSEIRB-MATMECA, Electronique 2A, 2020

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- delta-sigma modulator of order 2 (see Understanding Delta-Sigma Data Converter, Richard Schreier & Gabor C. Temes page 90)
--
--  (data_in) X(z)  18bits sign?---> + ---------(U(z))----------> 1 bit troncation ----------> Y(z) (data_out)
--                                   ^                     |     (sort either -2^17       |
--                                   |                     |      either +2^17            |
--                                   |                     v                            v
--                                   --- H1(z) <-(-E(z))-- + --(*-1)---------------------
--
--                                    H1(z) = z^-1 (2 - z^-1) = 2*z^-1 - z^2
--
--                                  we note d1 the register implemented by the delai z^-1
--                                    and d2 the register after the 2nd deadline.
--                            H(z) is a delay d1, followed by a sum of 2 times d1 and -d2, d2 being a new delay after d1
--
--                            the equations are therefore :
--                               u := x + 2*d1 - d2      (variable since no delay)
--                               y := 2^17 if u>=0 otherwise -2^17 ( truncation = DAC 1bit)
--                               d1 <= u - y    (register since delay)
--                               d2 <= d1       (register since delay)
--
--                             to avoid overflows, we add a lot of bits to u, d1, d2 and y (i.e. 32 signed bits...)
--                             we could also saturate d1 and d2.
--
--
-- E is the error due to 1 bit conversion (1 bit truncation)
--
-- usually, we describe the output signal Y = U + E, U the input signal (of the truncation) and E being the error.
--     on the drawing we make U - Y , so it is -E in input of H1(z).
--
--
-- the equation of the circuit is U(z) = Y(z) - E(z) (according to definition of E above)
--                           U(z) = X(z) + ( H1(z) * -E(z) ) ( equation according to the drawn circuit)
--                    soit Y - E = X - H1*E, Y = X + (1-H1)*E
--
--                      Y(z) = X(z) + ( 1 - H1(z) ) * E (z)
--
--    we choose H1(z) so as to minimize the error E(z) in the bandwidth,
--    so by trying to reject all equivalent noise in high frequencies,
--    that will be filtered by the external analog filter (or speaker)
--
--   the simplest is to use H1(z) = z^-1, (a simple delay).   (modulator order 1)
--        here we use a modulator of order 2
--


entity dsmod2 is
  port (
    clk  : in std_logic; -- 100MHz
    rst  : in boolean; -- reset synchrone

    clk_ce_in : in boolean; -- clock enable input, 2.5MHz
    data_in : in signed(17 downto 0); -- filtered oversample @ 2.5MHz

    data_out : out std_logic := '0' -- modulator output
    );
end entity;

architecture rtl of dsmod2 is

  signal x : signed(24 downto 0) := (others => '0'); -- buffer
  signal d1 : signed(24 downto 0) := (others => '0'); -- output first integrator
  signal d2 : signed(24 downto 0) := (others => '0'); -- output second integrator

begin

  process (clk)
    variable u : signed(24 downto 0); -- signal before truncation
    variable y : signed(24 downto 0); -- output (converted back to PCM)
    variable e : signed(24 downto 0); -- error (before integrators)
  begin

    if rising_edge(clk) then

      if clk_ce_in then

        x <= resize (data_in,x'length);

        u := x + shift_left(d1,1) - d2;  -- x + 2*d1 - d2

        if (u>=0) then
          data_out <= '1';
          y := to_signed(2**17-1,y'length);
        else
          data_out <= '0';
          y := to_signed(-2**17,y'length);
        end if;

        e := u - y; -- (-e l'erreur)
--        if (e>=(2**19-1)) then -- saturation positive
--          d1 <= to_signed(2**19-1,d1'length);
--        elsif (e<=-2**19) then -- saturation negative
--          d1 <= to_signed(-2**19,d1'length);
--        else
          d1 <= e;
--        end if;

        d2 <= d1;

      end if;


      if rst then
          d1 <= (others => '0');
          d2 <= (others => '0');
          data_out <= '0';
      end if;

    end if; -- clk

    
  end process;

end architecture;
