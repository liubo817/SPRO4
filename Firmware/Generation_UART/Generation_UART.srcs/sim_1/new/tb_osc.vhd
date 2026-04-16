library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

    -- Slow baud so UART fits in reasonable sim time
    constant CLK_HZ     : integer := 100_000_000;
    constant BAUD       : integer := 1_000_000;   -- faster baud for simulation
    constant CLK_PERIOD : time    := 10 ns;
    constant BIT_PERIOD : time    := 1_000_000 ns / BAUD;

    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal i_rx        : std_logic := '1';  -- idle high
    signal o_tx        : std_logic;
    signal i_adc_data  : std_logic_vector(7 downto 0) := x"AB";
    signal i_adc_valid : std_logic := '0';
    signal o_tx_busy   : std_logic;
    signal pwm_out     : std_logic;
    signal saw_out     : std_logic_vector(7 downto 0);

    -- Task: send one UART byte on i_rx
    procedure uart_send_byte (
        constant byte_val : in std_logic_vector(7 downto 0);
        signal   rx_line  : out std_logic
    ) is
    begin
        -- Start bit
        rx_line <= '0';
        wait for BIT_PERIOD;
        -- Data bits LSB first
        for i in 0 to 7 loop
            rx_line <= byte_val(i);
            wait for BIT_PERIOD;
        end loop;
        -- Stop bit
        rx_line <= '1';
        wait for BIT_PERIOD;
    end procedure;

begin

    DUT : osc
        generic map (
            G_CLK_HZ  => CLK_HZ,
            G_BAUD    => BAUD,
            CLK_DIV_N => 1        -- fastest waves for simulation
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
        -- -----------------------------------------------
        -- Reset
        -- -----------------------------------------------
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 100 ns;

        -- -----------------------------------------------
        -- TEST 1: Send duty=0x40 (25%), wave_sel=0 (PWM)
        -- -----------------------------------------------
        report "TEST 1: Sending duty=0x40, wave_sel=PWM";
        uart_send_byte(x"40", i_rx);  -- duty = 64
        uart_send_byte(x"00", i_rx);  -- wave_sel = PWM
        wait for BIT_PERIOD * 4;

        report "TEST 1: Check pwm_out toggling in waveform viewer";

        -- -----------------------------------------------
        -- TEST 2: Send duty=0x80 (50%), wave_sel=0 (PWM)
        -- -----------------------------------------------
        report "TEST 2: Sending duty=0x80, wave_sel=PWM";
        uart_send_byte(x"80", i_rx);  -- duty = 128
        uart_send_byte(x"00", i_rx);  -- wave_sel = PWM
        wait for BIT_PERIOD * 4;

        report "TEST 2: PWM duty widened, check waveform viewer";

        -- -----------------------------------------------
        -- TEST 3: Switch to sawtooth mode
        -- -----------------------------------------------
        report "TEST 3: Sending wave_sel=Sawtooth";
        uart_send_byte(x"00", i_rx);  -- duty irrelevant
        uart_send_byte(x"01", i_rx);  -- wave_sel = Sawtooth
        wait for CLK_PERIOD * 512;    -- watch 2 full sawtooth ramps

        report "TEST 3: saw_out should ramp 0->255, check waveform viewer";

        -- -----------------------------------------------
        -- TEST 4: Trigger ADC transmit back to Python
        -- -----------------------------------------------
        report "TEST 4: Pulsing ADC valid";
        i_adc_data  <= x"CD";
        i_adc_valid <= '1';
        wait for CLK_PERIOD;
        i_adc_valid <= '0';

        -- Wait for TX to finish
        wait until o_tx_busy = '0';
        report "TEST 4: ADC byte transmitted on o_tx";

        report "ALL TESTS DONE - inspect waveform viewer";
        wait;
    end process;

end Behavioral;