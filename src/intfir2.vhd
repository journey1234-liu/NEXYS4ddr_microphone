-- GUENEGO Louis
-- ENSEIRB-MATMECA, Electronique 2A, 2020

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


-- x8 oversample/filter
--
-- 1) the signal is oversampled by a factor x8 (7 samples are added to 0 intermediate)
-- 2) we filter (FIR passes low) so as to reconstruct the oversampled signal perfectly, removing
--      spectrum repetition from oversampling
--
-- The low-pass FIR filter has 128-8 = 120 samples, so that the circular memory contains 16 samples
--  (it's easier for circular pointers, no need to test the overflow)
--
-- As 7/8 samples are worth 0, we can only multiply all 8 (the result of the others is obviously 0)
--
-- In the circular memory, we store only 1/8 or 16 in total, (the others are worth 0, no need to store them)
--
-- Each time a new sample is inserted into the circular memory 8 on samples filtered at the output
--   by making 120 coef*ech multiplications.  (15 per oversample)
--
-- Here we go through the filter from the sample + recent (we over-sample, the 8 over-samples must be produced before the next ech)
--  We increment the indices of the samples (and therefore of the coef)
--  The oldest oversample (the n-7) is first produced until the most recent.  The most recent one uses the most recent sample (here 15),
--  so the others start a little before and therefore will use the n-1 sample first (here 14)
--    (reminder: the over-samples at 0 are not calculated or stored, they are virtual...)
--
--   ech   15 . . . . . . . 14 . . . . . . . 13 . . . . . . . 12 .  (...)   . 1 . . . . . . 0 . . . . . . .  (the.  are the 0 inserted virtually)
--     (le + recent)                                                                (le + ancien)
--  (here we indicate the coef to be used for each on filtered sample)
--  sef-7                  0 1  2 3 4         9               17             105           113     118 119 -
--  sef-6                0 1 2  3 4          10               18             106           114     119  -  -
--
--  sef-1     0 1 2 3 4 5 6  7               15               23             111           119 - - - - - - -
--  sef-0   0 1 2 3 4 5 6 7  8               16               24             112       119  -  - - - - - - -
--
-- We see that the calculation of filtered over-samples -7 to -1 starts at sample 14 (ech-1) and go up to sample 0
--   while the most recent filtered oversample (0) starts at sample 15 (ech-0) and goes all the way to sample 1.
--
-- We see that if we had taken a filter with 128 coefficients (the same as fir1), then we would have had to make a circular memory on 17
-- samples, but then the pointers are less easy to manage (the return to 0 is not simple while it is with a power of 2)
--
-- We aim for a signed 18x18 multiplier, so numbers up to +/-2^17-1
--  This is the case of input samples, is also coefficients thanks to adequate normalization (2^21)
--  filtered oversamplings nevertheless need an x8 factor, since the power was spread over the entire spectrum and then filtered, which
--  removes 7/8 of the power by cutting off all spectrum replications.
--
--
-- In the end the calculation of each oversample takes 15 cycles + the latency of start-up of the pipeline, (6-7 clock) and we do not use
--   only one wired multiplier (block DSP48) and a single accumulator.
--
-- LOW-pass FIR filter and decimator by 8
-- it must perfectly cut after 312.5kHz/2 and be flat gain=0dB from about 0 to 10kHz
--   Iowa Hills FIR Filter Designer Version 7.0, freeware
--   Sampling Freq 2500000
--   Fc = 0,05 (62.5kHz)
--   Kaiser Beta 10, Window Kaiser, Rectangle 1,000
--   120 taps (=coefficients)
--   0..-0.03dB up to 20kHz and > -90dB after 150kHz
--
--

entity intfir2 is
  port (
    clk  : in std_logic; -- 100MHz
    rst  : in boolean; -- synchronous reset

    clk_ce_in : in boolean; -- clock enable input, 312.5kHz
    data_in : in signed(17 downto 0); -- intermediate sample, from fir1

    clk_ce_out : in boolean; -- clock enable oversampling 312.5*8 = 2.5MkHz, occurs at the same time as clk_ce_in (1 time / 8)
    ech_out : out signed(17 downto 0) := (others => '0') -- output filtered oversampled sample, 18bits signed, valid when clk_ce_out is active
    );
  end entity;

architecture rtl of intfir2 is

-- FIR filter coefficients:
  type coef_mem_t is  array (natural range <>) of signed(17 downto 0);
  signal coef_mem : coef_mem_t(0 to 128-1) := (  -- only 248 coefs are used, but size at 256 to avoid errors in index simulation >= 248
-- FIR low pass filter generated with Iowa Hills FIR Filter Designer Version 7.0 - Freeware
--   Sampling Freq=2500000  , Fc=0.05 (62.5kHz), Num Taps=120, Kaiser Beta=10, Window Kaiser, 1,000 Rectangle 73.85kHz
--   Normalization of coefficient to 2^21 and rounded to the nearest integer (max abs=123750 = 16.92bits => fits on 17+1 = 18bits signed)
--   (filter control by reloading coefficients in Iowa Hills FIR Filter Designer => difference to the naked eye.
-- note: the filter is symmetrical, coef(0) = coef(119), coef(1) = coef(118) ...  coef(59)=coef(60)
    0   => to_signed( -8     , 18),
    1   => to_signed( -14    , 18),
    2   => to_signed( -21    , 18),
    3   => to_signed( -29    , 18),
    4   => to_signed( -37    , 18),
    5   => to_signed( -43    , 18),
    6   => to_signed( -44    , 18),
    7   => to_signed( -38    , 18),
    8   => to_signed( -22    , 18),
    9   => to_signed( 9      , 18),
    10  => to_signed( 59     , 18),
    11  => to_signed( 131    , 18),
    12  => to_signed( 228    , 18),
    13  => to_signed( 351    , 18),
    14  => to_signed( 500    , 18),
    15  => to_signed( 671    , 18),
    16  => to_signed( 858    , 18),
    17  => to_signed( 1051   , 18),
    18  => to_signed( 1235   , 18),
    19  => to_signed( 1393   , 18),
    20  => to_signed( 1503   , 18),
    21  => to_signed( 1541   , 18),
    22  => to_signed( 1480   , 18),
    23  => to_signed( 1293   , 18),
    24  => to_signed( 955    , 18),
    25  => to_signed( 445    , 18),
    26  => to_signed( -255   , 18),
    27  => to_signed( -1152  , 18),
    28  => to_signed( -2243  , 18),
    29  => to_signed( -3512  , 18),
    30  => to_signed( -4927  , 18),
    31  => to_signed( -6443  , 18),
    32  => to_signed( -7994  , 18),
    33  => to_signed( -9500  , 18),
    34  => to_signed( -10865 , 18),
    35  => to_signed( -11979 , 18),
    36  => to_signed( -12724 , 18),
    37  => to_signed( -12975 , 18),
    38  => to_signed( -12607 , 18),
    39  => to_signed( -11500 , 18),
    40  => to_signed( -9545  , 18),
    41  => to_signed( -6651  , 18),
    42  => to_signed( -2753  , 18),
    43  => to_signed( 2187   , 18),
    44  => to_signed( 8173   , 18),
    45  => to_signed( 15168  , 18),
    46  => to_signed( 23100  , 18),
    47  => to_signed( 31852  , 18),
    48  => to_signed( 41272  , 18),
    49  => to_signed( 51171  , 18),
    50  => to_signed( 61330  , 18),
    51  => to_signed( 71506  , 18),
    52  => to_signed( 81442  , 18),
    53  => to_signed( 90872  , 18),
    54  => to_signed( 99538  , 18),
    55  => to_signed( 107191 , 18),
    56  => to_signed( 113609 , 18),
    57  => to_signed( 118601 , 18),
    58  => to_signed( 122016 , 18),
    59  => to_signed( 123750 , 18),
    60  => to_signed( 123750 , 18),
    61  => to_signed( 122016 , 18),
    62  => to_signed( 118601 , 18),
    63  => to_signed( 113609 , 18),
    64  => to_signed( 107191 , 18),
    65  => to_signed( 99538  , 18),
    66  => to_signed( 90872  , 18),
    67  => to_signed( 81442  , 18),
    68  => to_signed( 71506  , 18),
    69  => to_signed( 61330  , 18),
    70  => to_signed( 51171  , 18),
    71  => to_signed( 41272  , 18),
    72  => to_signed( 31852  , 18),
    73  => to_signed( 23100  , 18),
    74  => to_signed( 15168  , 18),
    75  => to_signed( 8173   , 18),
    76  => to_signed( 2187   , 18),
    77  => to_signed( -2753  , 18),
    78  => to_signed( -6651  , 18),
    79  => to_signed( -9545  , 18),
    80  => to_signed( -11500 , 18),
    81  => to_signed( -12607 , 18),
    82  => to_signed( -12975 , 18),
    83  => to_signed( -12724 , 18),
    84  => to_signed( -11979 , 18),
    85  => to_signed( -10865 , 18),
    86  => to_signed( -9500  , 18),
    87  => to_signed( -7994  , 18),
    88  => to_signed( -6443  , 18),
    89  => to_signed( -4927  , 18),
    90  => to_signed( -3512  , 18),
    91  => to_signed( -2243  , 18),
    92  => to_signed( -1152  , 18),
    93  => to_signed( -255   , 18),
    94  => to_signed( 445    , 18),
    95  => to_signed( 955    , 18),
    96  => to_signed( 1293   , 18),
    97  => to_signed( 1480   , 18),
    98  => to_signed( 1541   , 18),
    99  => to_signed( 1503   , 18),
    100 => to_signed( 1393   , 18),
    101 => to_signed( 1235   , 18),
    102 => to_signed( 1051   , 18),
    103 => to_signed( 858    , 18),
    104 => to_signed( 671    , 18),
    105 => to_signed( 500    , 18),
    106 => to_signed( 351    , 18),
    107 => to_signed( 228    , 18),
    108 => to_signed( 131    , 18),
    109 => to_signed( 59     , 18),
    110 => to_signed( 9      , 18),
    111 => to_signed( -22    , 18),
    112 => to_signed( -38    , 18),
    113 => to_signed( -44    , 18),
    114 => to_signed( -43    , 18),
    115 => to_signed( -37    , 18),
    116 => to_signed( -29    , 18),
    117 => to_signed( -21    , 18),
    118 => to_signed( -14    , 18),
    119 => to_signed( -8     , 18),
    others => to_signed( 0   , 18) -- avoids index errors >=120
           );

  signal coef_out : signed(17 downto 0);
  signal coef_out_reg : signed(17 downto 0);

  -- circular memory to keep the last 32 samples
  type data_in_mem_t is  array (natural range <>) of signed(17 downto 0);
  signal data_in_mem : data_in_mem_t(0 to 16-1) := ( others => to_signed(0,18) ); -- preinit to 0
  signal data_out : signed(17 downto 0);
  signal data_out_reg : signed(17 downto 0);

  signal ptr_in : unsigned(3 downto 0) := (others => '0'); -- sample input pointer
  signal ptr_out : unsigned(3 downto 0) := (others => '0'); -- filter calculation pointer
  signal ptr_out_save : unsigned(3 downto 0) := (others => '0');
  signal ptr_out_last : unsigned(3 downto 0) := (others => '0');
  signal ptr_out_reg : unsigned(3 downto 0) := (others => '0'); -- filter calculation pointer
  signal ptr_coef : unsigned(6 downto 0) := (others => '0'); -- coefficient pointer
  signal ptr_coef_reg : unsigned(6 downto 0); -- coefficient pointer

  signal cpt : integer range 0 to 16+10 := 0; -- filter calculation state machine index, 128 + init pipeline & normalization / saturation result
  signal cpt_surech : integer range 0 to 7 := 7; -- counts oversample produced with output cycle

  signal acc : signed(19+17 downto 0) := (others => '0'); -- the coef are normalized to 2^21, the samples to 2^17, we accumulate 32x
    -- the sum of the absolute values of the coef is 2608724, = 21.32bits, so we can not exceed 22+ 17+1 (sign) bits
    -- more precisely, as we use only 1 coef out of 8, we look in excel (intfir2.xls) for the max of absolute values
    --   of each of the coef sequences by taking 1/8.   This is 333251, i.e. 18,353 bits, so we can not exceed 19 + 17 + 1 (sign) bits

  signal mul_data_coef : signed(18+18-1 downto 0);  -- signed 18x18-bit multiplier output
  signal mul_data_coef_reg : signed(18+18-1 downto 0);


  begin

  process (clk)

    begin

    if rising_edge(clk) then

      if clk_ce_in then
        data_in_mem(to_integer(ptr_in)) <= data_in; -- filled the circular memory with the input samples
        ptr_in <= ptr_in + 1; -- auto wrapping
        end if;

      if (cpt /= 0) then -- the filter rotates 8 times a clk_ce_out
        cpt <= cpt + 1;
        ptr_out <= ptr_out - 1; -- auto wrapping
        ptr_coef <= ptr_coef + 8;
        end if;

      if clk_ce_out then
        cpt <= 1;
        acc <= (others => '0');

        if clk_ce_in then -- starts the oversampling note: clk_ce_in occurs at the same time as clk_ce_out, 1 time out of 8,
          ptr_out <= ptr_in - 1;  -- ech-1 (ptr_in has not yet been incremented)
          ptr_out_save <= ptr_in - 1;
          ptr_out_last <= ptr_in; -- ech for the last
          ptr_coef <= to_unsigned(1,ptr_coef'length);
          cpt_surech <= 1;
        elsif (cpt_surech>0) then
          ptr_out <= ptr_out_save;  -- ech-1
          ptr_coef <= to_unsigned(cpt_surech,ptr_coef'length); -- starts with the last one (we could also start with the first since the filter is symmetrical)
        else -- cpt_surech=0 (last on sample, starting with the most recent sample)
          ptr_out <= ptr_out_last;  -- ech for the last
          ptr_coef <= to_unsigned(0,ptr_coef'length); -- starts with the last one (we could also start with the first since the filter is symmetrical)
          end if;

        end if;

      if (cpt>=6) and (cpt<15+6) then -- we accumulate once the pipeline is launched
        acc <= acc + mul_data_coef_reg; -- accumulator
      elsif (cpt=15+6) then -- end of decimation, normalization by 21-3 (filter coef normalized by 2^21, but oversampling by 8
        if (acc(acc'high downto 21-3) < -2**17) then  -- by adding zero => loss of amplitude of 1 factor 8 after filtering
          ech_out <= to_signed(-2**17,ech_out'length);
        elsif (acc(acc'high downto 21-3) > 2**17 - 1) then
          ech_out <= to_signed(2**17 - 1,ech_out'length);
        else
          ech_out <= acc(17+21-3 downto 21-3);
          end if;
        if (cpt_surech<7) then cpt_surech <= cpt_surech + 1; else cpt_surech <= 0; end if;
        cpt <= 0; -- end of this oversample, ready for the next one
        end if;

      ptr_out_reg <= ptr_out; -- buffers addresses and data output for max frequency!
      data_out <= data_in_mem(to_integer(ptr_out_reg)); -- we are not at one or 2 stroke of the clock ready and we have plenty of D rockers.
      data_out_reg <= data_out;

      ptr_coef_reg <= ptr_coef;
      coef_out <= coef_mem(to_integer(ptr_coef_reg));
      coef_out_reg <= coef_out;

      mul_data_coef <= data_out_reg * coef_out_reg; -- signed 18x18 multiplier
      mul_data_coef_reg <= mul_data_coef; -- buffer for max speed

      if rst then
          ptr_in <= (others => '0');
          cpt <= 0;
          ech_out <= to_signed(0,ech_out'length);
      end if;

      end if; -- clk


    end process;

  end architecture;


