library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity wave_generator_tb is
end wave_generator_tb;

architecture Behavioral of wave_generator_tb is

    component wave_generator
        Generic (CLK_DIV_N : integer := 4);
        Port (
            clk      : in  STD_LOGIC;
            reset    : in  STD_LOGIC;
            duty     : in  STD_LOGIC_VECTOR(7 downto 0);
            wave_sel : in  STD_LOGIC;
            pwm_out  : out STD_LOGIC;
            saw_out  : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;

    signal clk      : STD_LOGIC := '0';
    signal reset    : STD_LOGIC := '1';
    signal duty     : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal wave_sel : STD_LOGIC := '0';
    signal pwm_out  : STD_LOGIC;
    signal saw_out  : STD_LOGIC_VECTOR(7 downto 0);

begin

    uut : wave_generator
        generic map (CLK_DIV_N => 4)
        port map (
            clk      => clk,
            reset    => reset,
            duty     => duty,
            wave_sel => wave_sel,
            pwm_out  => pwm_out,
            saw_out  => saw_out
        );

    clk <= not clk after CLK_PERIOD / 2;

    process
    begin
        -- Reset
        reset <= '1';
        wait for 40 ns;
        reset <= '0';

        -- PWM mode, 50% duty
        wave_sel <= '0';
        duty     <= x"80";
        wait for 5000 ns;

        -- Sawtooth mode
        wave_sel <= '1';
        wait for 1000 ns;

        wait;
    end process;

end Behavioral;