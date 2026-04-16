library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity wave_generator is
    Generic (
        CLK_DIV_N : integer := 256  -- Divides 100MHz master clock
    );
    Port (
        clk        : in  STD_LOGIC;
        reset      : in  STD_LOGIC;
        duty       : in  STD_LOGIC_VECTOR(7 downto 0);  -- PWM duty (0-255)
        wave_sel   : in  STD_LOGIC;                      -- 0=PWM, 1=Sawtooth
        pwm_out    : out STD_LOGIC;
        saw_out    : out STD_LOGIC_VECTOR(7 downto 0)
    );
end wave_generator;

architecture Behavioral of wave_generator is

    -- Divided clock signal
    signal clk_divided : STD_LOGIC := '0';

    -- Internal wave counter (runs on divided clock)
    signal counter : unsigned(7 downto 0) := (others => '0');

    -- Clock divider counter
    signal div_counter : integer range 0 to CLK_DIV_N/2 - 1 := 0;

begin

    -- Clock divider (your nDivider logic, inlined here)
    process(clk, reset)
    begin
        if reset = '1' then
            div_counter  <= 0;
            clk_divided  <= '0';
        elsif rising_edge(clk) then
            if div_counter = (CLK_DIV_N/2 - 1) then
                clk_divided <= not clk_divided;
                div_counter <= 0;
            else
                div_counter <= div_counter + 1;
            end if;
        end if;
    end process;

    -- Wave counter (runs on divided clock)
    process(clk_divided, reset)
    begin
        if reset = '1' then
            counter <= (others => '0');
        elsif rising_edge(clk_divided) then
            counter <= counter + 1;  -- Natural 8-bit overflow: 255 → 0
        end if;
    end process;

    -- PWM output
    pwm_out <= '1' when (wave_sel = '0' and counter < unsigned(duty)) else '0';

    -- Sawtooth output
    saw_out <= STD_LOGIC_VECTOR(counter) when wave_sel = '1'
               else (others => '0');

end Behavioral;