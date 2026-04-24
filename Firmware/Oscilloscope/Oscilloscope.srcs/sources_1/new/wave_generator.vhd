-- =============================================================================
-- wave_generator.vhd
-- ZedBoard PL - PWM + Sawtooth wave generator with switchable frequency
--
-- Frequencies (4 DIP switches, one-hot):
--   SW0 → 100 Hz
--   SW1 → 200 Hz
--   SW2 → 500 Hz
--   SW3 → 1000 Hz
--
-- *** Key improvement over original ***
--   The original used clk_divided as a real clock, which creates a second
--   clock domain and causes synthesis/timing problems on FPGAs.
--   This version uses a single 100 MHz clock domain throughout, with a
--   clock-enable (clk_en) pulse to gate the wave counter instead.
--
-- Inputs:
--   clk      - 100 MHz system clock (GCLK on ZedBoard)
--   reset    - active-high synchronous reset
--   duty     - 8-bit PWM duty cycle (0 = 0%, 255 = ~100%)
--   wave_sel - 0 = PWM output active, 1 = Sawtooth output active
--   freq_sel - one-hot 4-bit: "0001"=100Hz "0010"=200Hz "0100"=500Hz "1000"=1kHz
--
-- Outputs:
--   pwm_out  - 1-bit PWM signal
--   saw_out  - 8-bit linear sawtooth (0x00 → 0xFF, wraps)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity wave_generator is
    Generic (
        CLK_FREQ_HZ : integer := 100_000_000   -- ZedBoard PL clock
    );
    Port (
        clk      : in  STD_LOGIC;
        reset    : in  STD_LOGIC;
        duty     : in  STD_LOGIC_VECTOR(7 downto 0);
        wave_sel : in  STD_LOGIC;
        freq_sel : in  STD_LOGIC_VECTOR(3 downto 0);  -- one-hot, see above
        pwm_out  : out STD_LOGIC;
        saw_out  : out STD_LOGIC_VECTOR(7 downto 0)
    );
end wave_generator;

architecture Behavioral of wave_generator is

    -- -------------------------------------------------------------------------
    -- Clock-enable divider constants
    --   Formula:  DIV = CLK_FREQ_HZ / (target_freq_Hz * 256)
    --   A free-running 8-bit counter (0-255) produces exactly target_freq_Hz
    --   full cycles per second when ticked at (target_freq * 256) Hz.
    --
    --   100 Hz  → 100 000 000 / (100  × 256) = 3906  (actual: 100.02 Hz)
    --   200 Hz  → 100 000 000 / (200  × 256) = 1953  (actual: 200.08 Hz)
    --   500 Hz  → 100 000 000 / (500  × 256) =  781  (actual: 500.32 Hz)
    --  1000 Hz  → 100 000 000 / (1000 × 256) =  390  (actual: 1001.6 Hz)
    -- -------------------------------------------------------------------------
    constant DIV_100HZ  : integer := CLK_FREQ_HZ / (100  * 256);   -- 3906
    constant DIV_200HZ  : integer := CLK_FREQ_HZ / (200  * 256);   -- 1953
    constant DIV_500HZ  : integer := CLK_FREQ_HZ / (500  * 256);   -- 781
    constant DIV_1KHZ   : integer := CLK_FREQ_HZ / (1000 * 256);   -- 390

    -- Use the largest divider as the counter ceiling (DIV_100HZ)
    signal clk_div_max  : integer range 1 to DIV_100HZ := DIV_100HZ;
    signal div_counter  : integer range 0 to DIV_100HZ := 0;
    signal clk_en       : STD_LOGIC := '0';

    -- Main wave counter
    signal counter      : unsigned(7 downto 0) := (others => '0');

    -- -------------------------------------------------------------------------
    -- 2-FF synchroniser registers for all async inputs (switches / buttons)
    -- Without these, metastability can corrupt the counter and divider logic.
    -- -------------------------------------------------------------------------
    signal freq_sel_s1, freq_sel_sync : STD_LOGIC_VECTOR(3 downto 0) := "0001";
    signal wave_sel_s1, wave_sel_sync : STD_LOGIC := '0';
    signal duty_s1,     duty_sync     : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

begin

    -- =========================================================================
    -- Stage 1: 2-FF input synchronisers
    --   All external inputs cross into the 100 MHz clock domain here.
    -- =========================================================================
    p_sync : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                freq_sel_s1   <= "0001";
                freq_sel_sync <= "0001";
                wave_sel_s1   <= '0';
                wave_sel_sync <= '0';
                duty_s1       <= (others => '0');
                duty_sync     <= (others => '0');
            else
                -- First FF
                freq_sel_s1   <= freq_sel;
                wave_sel_s1   <= wave_sel;
                duty_s1       <= duty;
                -- Second FF (resolved, safe to use)
                freq_sel_sync <= freq_sel_s1;
                wave_sel_sync <= wave_sel_s1;
                duty_sync     <= duty_s1;
            end if;
        end if;
    end process p_sync;

    -- =========================================================================
    -- Stage 2: Frequency selection - translate one-hot switch to divider value
    --   If no switch or multiple switches are active, defaults to 100 Hz.
    -- =========================================================================
    p_freq_sel : process(clk)
    begin
        if rising_edge(clk) then
            case freq_sel_sync is
                when "0001" => clk_div_max <= DIV_100HZ;
                when "0010" => clk_div_max <= DIV_200HZ;
                when "0100" => clk_div_max <= DIV_500HZ;
                when "1000" => clk_div_max <= DIV_1KHZ;
                when others => clk_div_max <= DIV_100HZ;  -- safe default
            end case;
        end if;
    end process p_freq_sel;

    -- =========================================================================
    -- Stage 3: Clock-enable generator
    --   Pulses clk_en for exactly ONE clock cycle at the chosen tick rate.
    --   Resets the counter when the frequency changes mid-operation to avoid
    --   a very long first period.
    -- =========================================================================
    p_clk_en : process(clk)
    begin
        if rising_edge(clk) then
            clk_en <= '0';                               -- default: de-asserted
            if reset = '1' then
                div_counter <= 0;
            elsif div_counter >= clk_div_max - 1 then   -- >= handles div change
                clk_en      <= '1';
                div_counter <= 0;
            else
                div_counter <= div_counter + 1;
            end if;
        end if;
    end process p_clk_en;

    -- =========================================================================
    -- Stage 4: Wave counter - 8-bit free-running, gated by clk_en
    -- =========================================================================
    p_counter : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter <= (others => '0');
            elsif clk_en = '1' then
                counter <= counter + 1;   -- wraps 255 → 0 automatically
            end if;
        end if;
    end process p_counter;

    -- =========================================================================
    -- Stage 5: Registered outputs
    --   Registered (not combinatorial) to avoid glitches on the output pins.
    -- =========================================================================
    p_outputs : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                pwm_out <= '0';
                saw_out <= (others => '0');
            elsif wave_sel_sync = '0' then
                -- PWM mode: high while counter < duty, low otherwise
                if counter < unsigned(duty_sync) then
                    pwm_out <= '1';
                else
                    pwm_out <= '0';
                end if;
                saw_out <= (others => '0');
            else
                -- Sawtooth mode: output tracks counter directly
                pwm_out <= '0';
                saw_out <= STD_LOGIC_VECTOR(counter);
            end if;
        end if;
    end process p_outputs;

end Behavioral;