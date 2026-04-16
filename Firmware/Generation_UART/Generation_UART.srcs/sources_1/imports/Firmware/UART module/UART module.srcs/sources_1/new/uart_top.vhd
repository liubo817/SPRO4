-- =============================================================================
-- uart_top.vhd  --  TX sends ADC data, RX receives duty/wave_sel commands
-- Protocol: Python sends 2 bytes: byte[0]=duty, byte[1]=wave_sel (0x00 or 0x01)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity uart_top is
    generic (
        G_CLK_HZ : integer := 100_000_000;
        G_BAUD   : integer := 115_200
    );
    port (
        i_clk       : in  std_logic;
        i_rst       : in  std_logic;
        -- ADC side (transmit)
        i_adc_data  : in  std_logic_vector(7 downto 0);
        i_adc_valid : in  std_logic;
        o_tx_busy   : out std_logic;
        o_tx        : out std_logic;
        -- FTDI receive
        i_rx        : in  std_logic;
        -- Wave generator control outputs
        o_duty      : out std_logic_vector(7 downto 0);
        o_wave_sel  : out std_logic
    );
end entity;

architecture Structural of uart_top is

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

    component uart_rx is
        generic (G_CLK_HZ : integer; G_BAUD : integer);
        port (
            i_clk   : in  std_logic;
            i_rst   : in  std_logic;
            i_rx    : in  std_logic;
            o_data  : out std_logic_vector(7 downto 0);
            o_valid : out std_logic
        );
    end component;

    signal rx_data  : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;

    -- Tracks whether next byte is duty or wave_sel
    signal rx_byte_idx : std_logic := '0';  -- 0=duty, 1=wave_sel

begin

    -- TX: send ADC data to Python
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

    -- RX: receive commands from Python
    u_rx : uart_rx
        generic map (G_CLK_HZ => G_CLK_HZ, G_BAUD => G_BAUD)
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_rx    => i_rx,
            o_data  => rx_data,
            o_valid => rx_valid
        );

    -- Command decoder: byte 0 = duty, byte 1 = wave_sel
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                o_duty      <= x"80";  -- default 50% duty
                o_wave_sel  <= '0';    -- default PWM mode
                rx_byte_idx <= '0';
            elsif rx_valid = '1' then
                if rx_byte_idx = '0' then
                    o_duty      <= rx_data;
                    rx_byte_idx <= '1';
                else
                    o_wave_sel  <= rx_data(0);  -- LSB = wave_sel
                    rx_byte_idx <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture;