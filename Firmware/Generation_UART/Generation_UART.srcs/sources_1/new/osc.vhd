-- =============================================================================
-- osc.vhd  --  Oscilloscope Top Level
-- Connects wave_generator and uart_top
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity osc is
    generic (
        G_CLK_HZ  : integer := 100_000_000;
        G_BAUD    : integer := 115_200;
        CLK_DIV_N : integer := 256
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        -- FTDI UART pins
        i_rx        : in  std_logic;
        o_tx        : out std_logic;
        -- ADC input
        i_adc_data  : in  std_logic_vector(7 downto 0);
        i_adc_valid : in  std_logic;
        o_tx_busy   : out std_logic;
        -- Wave output
        pwm_out     : out std_logic;
        saw_out     : out std_logic_vector(7 downto 0)
    );
end entity;

architecture Structural of osc is

    component uart_top is
        generic (G_CLK_HZ : integer; G_BAUD : integer);
        port (
            i_clk       : in  std_logic;
            i_rst       : in  std_logic;
            i_adc_data  : in  std_logic_vector(7 downto 0);
            i_adc_valid : in  std_logic;
            o_tx_busy   : out std_logic;
            o_tx        : out std_logic;
            i_rx        : in  std_logic;
            o_duty      : out std_logic_vector(7 downto 0);
            o_wave_sel  : out std_logic
        );
    end component;

    component wave_generator is
        generic (CLK_DIV_N : integer);
        port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            duty     : in  std_logic_vector(7 downto 0);
            wave_sel : in  std_logic;
            pwm_out  : out std_logic;
            saw_out  : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Internal wires between uart_top and wave_generator
    signal duty_sig     : std_logic_vector(7 downto 0);
    signal wave_sel_sig : std_logic;

begin

    u_uart : uart_top
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_BAUD   => G_BAUD
        )
        port map (
            i_clk       => clk,
            i_rst       => reset,
            i_adc_data  => i_adc_data,
            i_adc_valid => i_adc_valid,
            o_tx_busy   => o_tx_busy,
            o_tx        => o_tx,
            i_rx        => i_rx,
            o_duty      => duty_sig,
            o_wave_sel  => wave_sel_sig
        );

    u_wave : wave_generator
        generic map (
            CLK_DIV_N => CLK_DIV_N
        )
        port map (
            clk      => clk,
            reset    => reset,
            duty     => duty_sig,
            wave_sel => wave_sel_sig,
            pwm_out  => pwm_out,
            saw_out  => saw_out
        );

end architecture;