-- GUENEGO Louis
-- ENSEIRB-MATMECA, Electronique 2A, 2020

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- second FIR filter for decimation
--
-- LOW-pass FIR filter and decimator by 8
-- we go from 312.5kHz to 39.0625kHz with an anti-folding low-pass FIR filter synthesized with
--   Iowa Hills FIR Filter Designer Version 7.0, freeware
--   Sampling Freq 312500
--   Fc = 0,09 (14.06kHz)
--   Kaiser Beta 10, Window Kaiser
--   raised cosine = 1 (rectangle)
--   256 taps (=coefficients)
--   0..-0.03dB up to 11.75kHz and &lt;-90dB after 19kHz (Fs/2=39.0625kHz/2 => 19.5kHz to meet Shannon criterion)
--
-- The actual coefficients are normalized to 2^22 and rounded to the nearest signed integer (so 23bits signed).
-- The input samples are on 18bits signed, the goal being to use a wired multiplier Xilinx Artix7 DSP48 25*18bit.
--   The smallest coefficient is 2.66E-6 or 11 when normalized.
--   The largest coefficient is 0.0065699 or 27556 when normalized, which holds on 16 signed bit.
--    (with Excel and copied paste here.  Iowa Hills FIR Filter Designer Version 7.0 is also used to verify that rounding coefficients 
--         does not degrade the filter, by reloading the normalized and rounded coefficients)).
-- the final result reduced to 18bits signed.
-- Microphone samples are worth 0 or 1, considered here as -1 and +1 to remove the offset of 0.5.
--   If a PDM sample is 0, then the coefficient is subtracted
--   If a PDM sample is 1, then the coefficient is added
-- The accumulator is 24bits, the filter does not have an exceedance, we should not exceed 23bits signed in the end
--   the final result is normalized to 18 signed bits, and saturated as a precaution at +/-2^17-1
--

entity fir2 is
  port (
    clk  : in std_logic; -- 100MHz
    rst  : in boolean; -- synchronous reset
    
    clk_ce_in : in boolean; -- clock enable input, 312.5kHz
    data_in : in signed(17 downto 0); -- intermediate sample, from fir1

    clk_ce_out : in boolean; -- clock enable decimation 312.5Hz/8 = 39.0625kHz, occurs at the same time as clk_ce_in
    ech_out : out signed(17 downto 0) := (others => '0') -- output decimated samples, 18bits signed, valid when clk_ce_out is active
    );
  end entity;

architecture rtl of fir2 is

-- FIR filter coefficients:
  type coef_mem_t is  array (natural range <>) of signed(17 downto 0);
  signal coef_mem : coef_mem_t(0 to 256-1) := (
-- FIR low pass filter generated with Iowa Hills FIR Filter Designer Version 7.0 - Freeware
--   Sampling Freq=312500  , Fc=0.09 (14.06kHz), Num Taps=256, Kaiser Beta=10, Window Kaiser, 1,000 Rectangle 14.73kHz
--   Normalization of coefficient to 2^20 and rounded to the nearest integer (max abs=98543 = 16.6bit = &gt; fits on 17+1 = 18bits signed)
--   (filter control by reloading coefficients in Iowa Hills FIR Filter Designer => difference to the naked eye.
-- note: the filter is symmetrical, coef(0) = coef(255), coef(1) = coef(254) ...  coef(127)=coef(128)
    0   => to_signed( 0      , 18),
    1   => to_signed( 0      , 18),
    2   => to_signed( -1     , 18),
    3   => to_signed( -2     , 18),
    4   => to_signed( -3     , 18),
    5   => to_signed( -5     , 18),
    6   => to_signed( -6     , 18),
    7   => to_signed( -7     , 18),
    8   => to_signed( -6     , 18),
    9   => to_signed( -5     , 18),
    10  => to_signed( -3     , 18),
    11  => to_signed( 0      , 18),
    12  => to_signed( 5      , 18),
    13  => to_signed( 11     , 18),
    14  => to_signed( 17     , 18),
    15  => to_signed( 23     , 18),
    16  => to_signed( 28     , 18),
    17  => to_signed( 31     , 18),
    18  => to_signed( 31     , 18),
    19  => to_signed( 28     , 18),
    20  => to_signed( 20     , 18),
    21  => to_signed( 8      , 18),
    22  => to_signed( -9     , 18),
    23  => to_signed( -28    , 18),
    24  => to_signed( -49    , 18),
    25  => to_signed( -69    , 18),
    26  => to_signed( -86    , 18),
    27  => to_signed( -98    , 18),
    28  => to_signed( -102   , 18),
    29  => to_signed( -95    , 18),
    30  => to_signed( -76    , 18),
    31  => to_signed( -46    , 18),
    32  => to_signed( -4     , 18),
    33  => to_signed( 46     , 18),
    34  => to_signed( 101    , 18),
    35  => to_signed( 156    , 18),
    36  => to_signed( 205    , 18),
    37  => to_signed( 241    , 18),
    38  => to_signed( 259    , 18),
    39  => to_signed( 254    , 18),
    40  => to_signed( 221    , 18),
    41  => to_signed( 161    , 18),
    42  => to_signed( 73     , 18),
    43  => to_signed( -36    , 18),
    44  => to_signed( -159   , 18),
    45  => to_signed( -285   , 18),
    46  => to_signed( -403   , 18),
    47  => to_signed( -499   , 18),
    48  => to_signed( -559   , 18),
    49  => to_signed( -573   , 18),
    50  => to_signed( -531   , 18),
    51  => to_signed( -431   , 18),
    52  => to_signed( -274   , 18),
    53  => to_signed( -68    , 18),
    54  => to_signed( 174    , 18),
    55  => to_signed( 432    , 18),
    56  => to_signed( 683    , 18),
    57  => to_signed( 900    , 18),
    58  => to_signed( 1058   , 18),
    59  => to_signed( 1134   , 18),
    60  => to_signed( 1109   , 18),
    61  => to_signed( 974    , 18),
    62  => to_signed( 727    , 18),
    63  => to_signed( 379    , 18),
    64  => to_signed( -48    , 18),
    65  => to_signed( -523   , 18),
    66  => to_signed( -1004  , 18),
    67  => to_signed( -1446  , 18),
    68  => to_signed( -1801  , 18),
    69  => to_signed( -2025  , 18),
    70  => to_signed( -2081  , 18),
    71  => to_signed( -1944  , 18),
    72  => to_signed( -1606  , 18),
    73  => to_signed( -1077  , 18),
    74  => to_signed( -387   , 18),
    75  => to_signed( 416    , 18),
    76  => to_signed( 1268   , 18),
    77  => to_signed( 2091   , 18),
    78  => to_signed( 2805   , 18),
    79  => to_signed( 3329   , 18),
    80  => to_signed( 3594   , 18),
    81  => to_signed( 3547   , 18),
    82  => to_signed( 3159   , 18),
    83  => to_signed( 2433   , 18),
    84  => to_signed( 1402   , 18),
    85  => to_signed( 131    , 18),
    86  => to_signed( -1284  , 18),
    87  => to_signed( -2724  , 18),
    88  => to_signed( -4056  , 18),
    89  => to_signed( -5144  , 18),
    90  => to_signed( -5860  , 18),
    91  => to_signed( -6098  , 18),
    92  => to_signed( -5788  , 18),
    93  => to_signed( -4902  , 18),
    94  => to_signed( -3463  , 18),
    95  => to_signed( -1549  , 18),
    96  => to_signed( 713    , 18),
    97  => to_signed( 3147   , 18),
    98  => to_signed( 5545   , 18),
    99  => to_signed( 7681   , 18),
    100 => to_signed( 9328   , 18),
    101 => to_signed( 10280  , 18),
    102 => to_signed( 10371  , 18),
    103 => to_signed( 9496   , 18),
    104 => to_signed( 7624   , 18),
    105 => to_signed( 4810   , 18),
    106 => to_signed( 1198   , 18),
    107 => to_signed( -2980  , 18),
    108 => to_signed( -7415  , 18),
    109 => to_signed( -11738 , 18),
    110 => to_signed( -15542 , 18),
    111 => to_signed( -18413 , 18),
    112 => to_signed( -19956 , 18),
    113 => to_signed( -19828 , 18),
    114 => to_signed( -17768 , 18),
    115 => to_signed( -13621 , 18),
    116 => to_signed( -7356  , 18),
    117 => to_signed( 923    , 18),
    118 => to_signed( 10975  , 18),
    119 => to_signed( 22431  , 18),
    120 => to_signed( 34814  , 18),
    121 => to_signed( 47561  , 18),
    122 => to_signed( 60057  , 18),
    123 => to_signed( 71677  , 18),
    124 => to_signed( 81819  , 18),
    125 => to_signed( 89948  , 18),
    126 => to_signed( 95625  , 18),
    127 => to_signed( 98543  , 18),
    128 => to_signed( 98543  , 18),
    129 => to_signed( 95625  , 18),
    130 => to_signed( 89948  , 18),
    131 => to_signed( 81819  , 18),
    132 => to_signed( 71677  , 18),
    133 => to_signed( 60057  , 18),
    134 => to_signed( 47561  , 18),
    135 => to_signed( 34814  , 18),
    136 => to_signed( 22431  , 18),
    137 => to_signed( 10975  , 18),
    138 => to_signed( 923    , 18),
    139 => to_signed( -7356  , 18),
    140 => to_signed( -13621 , 18),
    141 => to_signed( -17768 , 18),
    142 => to_signed( -19828 , 18),
    143 => to_signed( -19956 , 18),
    144 => to_signed( -18413 , 18),
    145 => to_signed( -15542 , 18),
    146 => to_signed( -11738 , 18),
    147 => to_signed( -7415  , 18),
    148 => to_signed( -2980  , 18),
    149 => to_signed( 1198   , 18),
    150 => to_signed( 4810   , 18),
    151 => to_signed( 7624   , 18),
    152 => to_signed( 9496   , 18),
    153 => to_signed( 10371  , 18),
    154 => to_signed( 10280  , 18),
    155 => to_signed( 9328   , 18),
    156 => to_signed( 7681   , 18),
    157 => to_signed( 5545   , 18),
    158 => to_signed( 3147   , 18),
    159 => to_signed( 713    , 18),
    160 => to_signed( -1549  , 18),
    161 => to_signed( -3463  , 18),
    162 => to_signed( -4902  , 18),
    163 => to_signed( -5788  , 18),
    164 => to_signed( -6098  , 18),
    165 => to_signed( -5860  , 18),
    166 => to_signed( -5144  , 18),
    167 => to_signed( -4056  , 18),
    168 => to_signed( -2724  , 18),
    169 => to_signed( -1284  , 18),
    170 => to_signed( 131    , 18),
    171 => to_signed( 1402   , 18),
    172 => to_signed( 2433   , 18),
    173 => to_signed( 3159   , 18),
    174 => to_signed( 3547   , 18),
    175 => to_signed( 3594   , 18),
    176 => to_signed( 3329   , 18),
    177 => to_signed( 2805   , 18),
    178 => to_signed( 2091   , 18),
    179 => to_signed( 1268   , 18),
    180 => to_signed( 416    , 18),
    181 => to_signed( -387   , 18),
    182 => to_signed( -1077  , 18),
    183 => to_signed( -1606  , 18),
    184 => to_signed( -1944  , 18),
    185 => to_signed( -2081  , 18),
    186 => to_signed( -2025  , 18),
    187 => to_signed( -1801  , 18),
    188 => to_signed( -1446  , 18),
    189 => to_signed( -1004  , 18),
    190 => to_signed( -523   , 18),
    191 => to_signed( -48    , 18),
    192 => to_signed( 379    , 18),
    193 => to_signed( 727    , 18),
    194 => to_signed( 974    , 18),
    195 => to_signed( 1109   , 18),
    196 => to_signed( 1134   , 18),
    197 => to_signed( 1058   , 18),
    198 => to_signed( 900    , 18),
    199 => to_signed( 683    , 18),
    200 => to_signed( 432    , 18),
    201 => to_signed( 174    , 18),
    202 => to_signed( -68    , 18),
    203 => to_signed( -274   , 18),
    204 => to_signed( -431   , 18),
    205 => to_signed( -531   , 18),
    206 => to_signed( -573   , 18),
    207 => to_signed( -559   , 18),
    208 => to_signed( -499   , 18),
    209 => to_signed( -403   , 18),
    210 => to_signed( -285   , 18),
    211 => to_signed( -159   , 18),
    212 => to_signed( -36    , 18),
    213 => to_signed( 73     , 18),
    214 => to_signed( 161    , 18),
    215 => to_signed( 221    , 18),
    216 => to_signed( 254    , 18),
    217 => to_signed( 259    , 18),
    218 => to_signed( 241    , 18),
    219 => to_signed( 205    , 18),
    220 => to_signed( 156    , 18),
    221 => to_signed( 101    , 18),
    222 => to_signed( 46     , 18),
    223 => to_signed( -4     , 18),
    224 => to_signed( -46    , 18),
    225 => to_signed( -76    , 18),
    226 => to_signed( -95    , 18),
    227 => to_signed( -102   , 18),
    228 => to_signed( -98    , 18),
    229 => to_signed( -86    , 18),
    230 => to_signed( -69    , 18),
    231 => to_signed( -49    , 18),
    232 => to_signed( -28    , 18),
    233 => to_signed( -9     , 18),
    234 => to_signed( 8      , 18),
    235 => to_signed( 20     , 18),
    236 => to_signed( 28     , 18),
    237 => to_signed( 31     , 18),
    238 => to_signed( 31     , 18),
    239 => to_signed( 28     , 18),
    240 => to_signed( 23     , 18),
    241 => to_signed( 17     , 18),
    242 => to_signed( 11     , 18),
    243 => to_signed( 5      , 18),
    244 => to_signed( 0      , 18),
    245 => to_signed( -3     , 18),
    246 => to_signed( -5     , 18),
    247 => to_signed( -6     , 18),
    248 => to_signed( -7     , 18),
    249 => to_signed( -6     , 18),
    250 => to_signed( -5     , 18),
    251 => to_signed( -3     , 18),
    252 => to_signed( -2     , 18),
    253 => to_signed( -1     , 18),
    254 => to_signed( 0      , 18),
    255 => to_signed( 0      , 18)
           );

  signal coef_out : signed(17 downto 0);
  signal coef_out_reg : signed(17 downto 0);

  -- circular memory to keep the last 256 samples
  type data_in_mem_t is  array (natural range <>) of signed(17 downto 0);
  signal data_in_mem : data_in_mem_t(0 to 256-1) := ( others => to_signed(0,18) ); -- preinit to 0
  signal data_out : signed(17 downto 0);
  signal data_out_reg : signed(17 downto 0);

  signal ptr_in : unsigned(7 downto 0) := (others => '0'); -- sample input pointer
  signal ptr_out : unsigned(7 downto 0) := (others => '0'); -- filter calculation pointer
  signal ptr_out_reg : unsigned(7 downto 0) := (others => '0'); -- filter calculation pointer
  signal ptr_coef : unsigned(7 downto 0) := (others => '0'); -- coefficient pointer
  signal ptr_coef_reg : unsigned(7 downto 0); -- coefficient pointer

  signal cpt : integer range 0 to 256+10; -- filter calculation state machine index, 128 + init pipeline & normalization / saturation result

  signal acc : signed(21+17 downto 0) := (others => '0'); -- the coef are normalized to 2^20, the samples to 2^17, we accumulate 256x
    -- the sum of the absolute values of the coef is 1824350, = 20,8bits, so we can not exceed 21 + 17 + 1 (sign) bits

  signal mul_data_coef : signed(18+18-1 downto 0);  -- multiplier output
  signal mul_data_coef_reg : signed(18+18-1 downto 0);


  begin

  process (clk)

    begin

    if rising_edge(clk) then

      if clk_ce_in then
        data_in_mem(to_integer(ptr_in)) <= data_in; -- filled the circular memory with the input samples
        ptr_in <= ptr_in + 1; -- incrementation
      end if;

      if (clk_ce_out and (cpt=0)) then -- starts the decimator filter.  note: clk_ce_out occurs at the same time as clk_ce_in, 1 in 8 times,
        cpt <= cpt + 1; -- every 40*8 cycles = 320cycles at 100MHz.  The filter consumes about 130 cycles.
        ptr_out <= ptr_in + 1;  -- auto wrapping, starts with the oldest sample to prevent it from being crushed before it has been used...
        ptr_coef <= to_unsigned(255,ptr_coef'length); -- starts with the last one (we could also start with the first since the filter is symmetrical)
        acc <= (others => '0');
      end if;

      if (cpt /= 0) then -- the filter rotates
        cpt <= cpt + 1;
        ptr_out <= ptr_out + 1; -- (step 1 pipeline)
        ptr_coef <= ptr_coef - 1; -- (step 1 coef pipeline)
      end if;

      if (cpt>=6) and (cpt<256+6) then -- we accumulate once the pipeline is launched
        acc <= acc + mul_data_coef_reg; -- 18+18+8-bit accumulator = signed 44-bit (step 6 pipeline)
      elsif (cpt=256+6) then -- end of decimation, normalization by 19-17=2 bits and management of potential saturation
        if (acc(acc'high downto 20) < -2**17) then
          ech_out <= to_signed(-2**17,ech_out'length);
        elsif (acc(acc'high downto 20) > 2**17 - 1) then
          ech_out <= to_signed(2**17 - 1,ech_out'length);
        else
          ech_out <= acc(17+20 downto 20);
          end if;
        cpt <= 0; -- end of the decimator FIR, ready for the next decimation
        end if;

      ptr_out_reg <= ptr_out; -- buffers addresses and data output for max frequency!  (step 2 pipeline)
      data_out <= data_in_mem(to_integer(ptr_out_reg)); -- we are not at one or 2 strokes of the clock ready and we have plenty of D rockers. (step 3 pipeline)
      data_out_reg <= data_out; -- (step 4 pipeline)

      ptr_coef_reg <= ptr_coef; -- (step 2 pipeline coef)
      coef_out <= coef_mem(to_integer(ptr_coef_reg)); -- (step 3 pipeline coef)
      coef_out_reg <= coef_out; -- (step 4 pipeline coef)

      mul_data_coef <= data_out_reg * coef_out_reg; -- multiply 18x18 signed (step 5 fusion pipeline)
      mul_data_coef_reg <= mul_data_coef; -- buffer for max speed (step 6 pipeline)
      
      if rst then
          ptr_in <= (others => '0');
          cpt <= 0;
          ech_out <= to_signed(0,ech_out'length);
      end if;

    end if; -- clk

  end process;

end architecture;


