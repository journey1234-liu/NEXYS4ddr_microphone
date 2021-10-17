-- GUENEGO Louis
-- ENSEIRB-MATMECA, Electronique 2A, 2020


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


-- generating clocks
--
-- internally, only one clock is used at 100MHz, the sub-frequencies use the "clock enable" of the D toggles
--   this simplifies the management of clock/signal synchronization by limiting the number of clocks to 1
--
-- clk                     \_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?\_/?
--
-- clk_mic_pin       ______/???????\_______/???????\_______/???????\_______/???????\_   ( /40 actually)
-- clk_mic              ____/?\_____________/?\_____________/?\_____________/?\_________   (for DATA1 sampling at the clk_mig_pin)
--                               ---^                  ---^                                                                    ( sampling point)
-- clk_int                ____/?\_____________________________/?\_________________________  ( /8 actually)
-- clk_ech               ____________________________________/?\_________________________  ( /64 actually)


entity gest_freq is
  port (
    clk  : in std_logic; -- 100MHz
    rst  : in boolean; -- reset synchronous at release, asynchronous at assertion

    clk_mic_pin  : out std_logic := '0';  -- 2.5MHz ( /40 )

    clk_mic  : out boolean; -- top at 2.5MHz ( /40 )
    clk_int : out boolean; -- top at 312.5kHz  ( /8 )
    clk_ech  : out boolean  -- top at 39.0625kHz ( /8 )
    );
  end entity;

architecture rtl of gest_freq is


  -- integer with limited scope: makes writing code more readable,
  --   the compiler automatically deduces the number of bits needed
  --   the verification by the simulator is stricter.
  signal cpt_clk_mic : integer range 0 to 39 := 0; -- 100MHz => 2.5MHz (/40)
  signal cpt_clk_int : integer range 0 to 7 := 0; -- 2.5MHz => 312.5kHz (/8)
  signal cpt_clk_ech : integer range 0 to 7 := 0; -- 312.5kHz => 39.0625kHz (/8)

  signal clk_mic_pin1 : std_logic := '0'; -- delay clk_mic a stroke of the clock, allows to put the final D toggle in the IO
   -- and allows to well sample the input signal at the front rising of clk_pin (not 1 clock stroke = 10ns after)


  begin

  process (clk, rst)

    begin

    if rising_edge(clk) then

      if (cpt_clk_mic = 39) then -- /40
        cpt_clk_mic <= 0;
      else
        cpt_clk_mic <= cpt_clk_mic + 1;
      end if;

      if (cpt_clk_mic < 20) then  -- duty cycle 50%
        clk_mic_pin1 <= '1';
      else
        clk_mic_pin1 <= '0';
      end if;
      
      clk_mic_pin <= clk_mic_pin1; -- Switch D to IO and sync with internal clk_mic

      clk_mic <= false;
      clk_int <= false;
      clk_ech <= false;

      if (cpt_clk_mic = 0) then

        clk_mic <= true;

        if (cpt_clk_int = 7) then -- /8
          cpt_clk_int <= 0;
        else
          cpt_clk_int <= cpt_clk_int + 1;
        end if;

        if (cpt_clk_int = 0)  then

          clk_int <= true;

          if (cpt_clk_ech = 7)  then -- /8
            cpt_clk_ech <= 0;
          else
            cpt_clk_ech <= cpt_clk_ech + 1;
          end if;

          if (cpt_clk_ech = 0)  then -- /8
            clk_ech <= true;
                        
          end if;

        end if;

      end if;

    end if; -- clk

    if rst then
      cpt_clk_mic <= 0;
      cpt_clk_int <= 0;
      cpt_clk_ech <= 0;
      clk_mic_pin1 <= '0';
    end if;

  end process;

end architecture;
