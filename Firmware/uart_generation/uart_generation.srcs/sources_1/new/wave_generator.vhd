-- =============================================================================
-- wave_generator.vhd
--
-- Frequencies (4 DIP switches, one-hot):
--   SW0 → 100 Hz
--   SW1 → 200 Hz
--   SW2 → 500 Hz
--   SW3 → 1000 Hz
--   freq_sel - one-hot 4-bit: "0001"=100Hz "0010"=200Hz "0100"=500Hz "1000"=1kHz
-- =============================================================================
 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
 
entity wave_generator is
    Generic (
        CLK_FREQ_HZ : integer := 100_000_000
    );
    Port (
        clk      : in  STD_LOGIC;
        reset    : in  STD_LOGIC;
        duty     : in  STD_LOGIC_VECTOR(2 downto 0);  
        freq_sel : in  STD_LOGIC_VECTOR(3 downto 0);  
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
    constant DIV_100HZ : integer := CLK_FREQ_HZ / (100  * 256);  
    constant DIV_200HZ : integer := CLK_FREQ_HZ / (200  * 256);  
    constant DIV_500HZ : integer := CLK_FREQ_HZ / (500  * 256);  
    constant DIV_1KHZ  : integer := CLK_FREQ_HZ / (1000 * 256);  
 
    signal clk_div_max : integer range 1 to DIV_100HZ := DIV_100HZ;
    signal div_counter : integer range 0 to DIV_100HZ := 0;
    signal clk_en      : STD_LOGIC := '0';
 
    signal counter     : unsigned(7 downto 0) := (others => '0');
 
    signal freq_sel_s1, freq_sel_sync : STD_LOGIC_VECTOR(3 downto 0) := "0001";
    signal duty_s1,     duty_sync     : STD_LOGIC_VECTOR(2 downto 0) := (others => '0'); 
 
    signal duty_8bit : unsigned(7 downto 0);
 
begin
 
    -- duty_sync(2:0) padded with 5 LSB zeros → 8-bit threshold
    -- e.g. "101" → "10100000" = 0xA0 = 160 → 62.5% of 256
    duty_8bit <= unsigned(duty_sync & "00000");   
 
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