library ieee;
use ieee.std_logic_1164.all;

entity osc_tb is
end osc_tb;

architecture Behavioral of osc_tb is

    component osc is
        generic (
            G_CLK_HZ  : integer;
            G_BAUD    : integer;
            CLK_DIV_N : integer
        );
        port (
            clk         : in  std_logic;
            reset       : in  std_logic;
            i_rx        : in  std_logic;
            o_tx        : out std_logic;
            i_adc_data  : in  std_logic_vector(7 downto 0);
            i_adc_valid : in  std_logic;
            o_tx_busy   : out std_logic;
            pwm_out     : out std_logic;
            saw_out     : out std_logic_vector(7 downto 0)
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;

    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal i_rx        : std_logic := '1';
    signal o_tx        : std_logic;
    signal i_adc_data  : std_logic_vector(7 downto 0) := x"AB";
    signal i_adc_valid : std_logic := '0';
    signal o_tx_busy   : std_logic;
    signal pwm_out     : std_logic;
    signal saw_out     : std_logic_vector(7 downto 0);

begin

    DUT : osc
        generic map (
            G_CLK_HZ  => 100_000_000,
            G_BAUD    => 115_200,
            CLK_DIV_N => 1
        )
        port map (
            clk         => clk,
            reset       => reset,
            i_rx        => i_rx,
            o_tx        => o_tx,
            i_adc_data  => i_adc_data,
            i_adc_valid => i_adc_valid,
            o_tx_busy   => o_tx_busy,
            pwm_out     => pwm_out,
            saw_out     => saw_out
        );

    clk <= not clk after CLK_PERIOD / 2;

    process
    begin
        -- Reset
        reset <= '1';
        wait for 100 ns;
        reset <= '0';

        -- PWM mode, watch pwm_out toggle
        wait for 5000 ns;

        -- Pulse ADC valid
        i_adc_valid <= '1';
        wait for CLK_PERIOD;
        i_adc_valid <= '0';

        wait for 5000 ns;
        report "Done - check waveform viewer";
        wait;
    end process;

end Behavioral;