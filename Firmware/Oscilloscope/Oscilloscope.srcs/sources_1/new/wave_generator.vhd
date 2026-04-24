-- =============================================================================
-- wave_generator.vhd
-- ZedBoard PL - PWM generator with switchable frequency and duty cycle
--
-- Frequencies (4 DIP switches, one-hot):
--   SW0 → 100 Hz
--   SW1 → 200 Hz
--   SW2 → 500 Hz
--   SW3 → 1000 Hz
--
-- Inputs:
--   clk      - 100 MHz system clock (GCLK on ZedBoard)
--   reset    - active-high synchronous reset
--   duty     - 3-bit PWM duty (SW7=MSB, SW5=LSB): 8 levels
--               000=0%(0x00)  001=12.5%(0x20)  010=25%(0x40)  011=37.5%(0x60)
--               100=50%(0x80) 101=62.5%(0xA0)  110=75%(0xC0)  111=87.5%(0xE0)
--   freq_sel - one-hot 4-bit: "0001"=100Hz "0010"=200Hz "0100"=500Hz "1000"=1kHz
--
-- Outputs:
--   pwm_out  - 1-bit PWM signal
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
        duty     : in  STD_LOGIC_VECTOR(3 downto 0);  -- SW7=MSB, SW5=LSB
        freq_sel : in  STD_LOGIC_VECTOR(3 downto 0);  -- one-hot, see above
        pwm_out  : out STD_LOGIC
    );
end wave_generator;

architecture Behavioral of wave_generator is

    -- -------------------------------------------------------------------------
    -- Clock-enable divider constants
    --   Formula:  DIV = CLK_FREQ_HZ / (target_freq_Hz * 256)
    --
    --   100 Hz  → 100 000 000 / (100  × 256) = 3906  (actual: 100.02 Hz)
    --   200 Hz  → 100 000 000 / (200  × 256) = 1953  (actual: 200.08 Hz)
    --   500 Hz  → 100 000 000 / (500  × 256) =  781  (actual: 500.32 Hz)
    --  1000 Hz  → 100 000 000 / (1000 × 256) =  390  (actual: 1001.6 Hz)
    -- -------------------------------------------------------------------------
    constant DIV_100HZ : integer := CLK_FREQ_HZ / (100  * 256);  -- 3906
    constant DIV_200HZ : integer := CLK_FREQ_HZ / (200  * 256);  -- 1953
    constant DIV_500HZ : integer := CLK_FREQ_HZ / (500  * 256);  --  781
    constant DIV_1KHZ  : integer := CLK_FREQ_HZ / (1000 * 256);  --  390

    signal clk_div_max : integer range 1 to DIV_100HZ := DIV_100HZ;
    signal div_counter : integer range 0 to DIV_100HZ := 0;
    signal clk_en      : STD_LOGIC := '0';

    signal counter     : unsigned(7 downto 0) := (others => '0');

    -- 2-FF synchroniser registers for all async inputs
    signal freq_sel_s1, freq_sel_sync : STD_LOGIC_VECTOR(3 downto 0) := "0001";
    signal duty_s1,     duty_sync     : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');

    -- 3-bit duty expanded to 8-bit threshold (placed at bits [7:5])
    signal duty_8bit : unsigned(7 downto 0);

begin

    duty_8bit <= unsigned(duty_sync & "0000");

    -- =========================================================================
    -- Stage 1: 2-FF input synchronisers
    -- =========================================================================
    p_sync : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                freq_sel_s1   <= "0001";
                freq_sel_sync <= "0001";
                duty_s1       <= (others => '0');
                duty_sync     <= (others => '0');
            else
                freq_sel_s1   <= freq_sel;
                duty_s1       <= duty;
                freq_sel_sync <= freq_sel_s1;
                duty_sync     <= duty_s1;
            end if;
        end if;
    end process p_sync;

    -- =========================================================================
    -- Stage 2: Frequency selection
    -- =========================================================================
    p_freq_sel : process(clk)
    begin
        if rising_edge(clk) then
            case freq_sel_sync is
                when "0001" => clk_div_max <= DIV_100HZ;
                when "0010" => clk_div_max <= DIV_200HZ;
                when "0100" => clk_div_max <= DIV_500HZ;
                when "1000" => clk_div_max <= DIV_1KHZ;
                when others => clk_div_max <= DIV_100HZ;
            end case;
        end if;
    end process p_freq_sel;

    -- =========================================================================
    -- Stage 3: Clock-enable generator
    -- =========================================================================
    p_clk_en : process(clk)
    begin
        if rising_edge(clk) then
            clk_en <= '0';
            if reset = '1' then
                div_counter <= 0;
            elsif div_counter >= clk_div_max - 1 then
                clk_en      <= '1';
                div_counter <= 0;
            else
                div_counter <= div_counter + 1;
            end if;
        end if;
    end process p_clk_en;

    -- =========================================================================
    -- Stage 4: Wave counter
    -- =========================================================================
    p_counter : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter <= (others => '0');
            elsif clk_en = '1' then
                counter <= counter + 1;
            end if;
        end if;
    end process p_counter;

    -- =========================================================================
    -- Stage 5: PWM output
    -- =========================================================================
    p_outputs : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                pwm_out <= '0';
            elsif counter < duty_8bit then
                pwm_out <= '1';
            else
                pwm_out <= '0';
            end if;
        end if;
    end process p_outputs;

end Behavioral;