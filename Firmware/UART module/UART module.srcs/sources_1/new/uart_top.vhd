-- =============================================================================
-- uart_top.vhd  --  Feed ADC bytes into UART TX
--
-- Your ADC logic drives i_adc_data and pulses i_adc_valid for ONE clock cycle
-- when a new byte is ready.  Do not pulse again until o_tx_busy goes low.
--
-- Wire o_tx to your FTDI RXD pin.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity uart_top is
    generic (
        G_CLK_HZ : integer := 100_000_000;  -- 100 MHz Zedboard PL clock
        G_BAUD   : integer := 115_200        -- match your PC serial port
    );
    port (
        i_clk       : in  std_logic;
        i_rst       : in  std_logic;

        -- From your ADC / signal-capture logic
        i_adc_data  : in  std_logic_vector(7 downto 0);
        i_adc_valid : in  std_logic;   -- pulse 1 clk when data is ready
        o_tx_busy   : out std_logic;   -- do not send when this is high

        -- To FTDI module
        o_tx        : out std_logic
    );
end entity;

architecture rtl of uart_top is

    component uart_tx is
        generic (G_CLK_HZ : integer; G_BAUD : integer);
        port (
            i_clk   : in  std_logic;
            i_rst   : in  std_logic;
            i_data  : in  std_logic_vector(7 downto 0);
            i_valid : in  std_logic;
            o_busy  : out std_logic;
            o_tx    : out std_logic
        );
    end component;

begin

    u_tx : uart_tx
        generic map (G_CLK_HZ => G_CLK_HZ, G_BAUD => G_BAUD)
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_data  => i_adc_data,
            i_valid => i_adc_valid,
            o_busy  => o_tx_busy,
            o_tx    => o_tx
        );

end architecture;