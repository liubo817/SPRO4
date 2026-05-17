-- =============================================================================
-- uart_top_tb.vhd  --  Simple testbench for uart_top
-- VHDL-93 compatible (works in Vivado XSim, GHDL, ModelSim)
--
-- What it does:
--   Simulates your ADC sending 8 bytes one after another and prints
--   PASS/FAIL for each one received back on the TX line.
--
-- Vivado: add all 3 files to sim_1, set uart_top_tb as top, run sim to 5 ms
-- GHDL:
--   ghdl -a --std=93 uart_tx.vhd uart_top.vhd uart_top_tb.vhd
--   ghdl -e --std=93 uart_top_tb
--   ghdl -r --std=93 uart_top_tb --vcd=tb.vcd --stop-time=5ms
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_top_tb is
end entity;

architecture sim of uart_top_tb is

    -- 10 MHz clock, 1 Mbaud  ->  10 ticks per bit, fast simulation
    constant C_CLK_HZ     : integer := 10_000_000;
    constant C_BAUD       : integer := 1_000_000;
    constant C_CLK_PERIOD : time    := 100 ns;
    constant C_BIT_PERIOD : time    := 1000 ns;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal adc_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal adc_valid : std_logic := '0';
    signal tx_busy   : std_logic;
    signal tx_line   : std_logic;

    component uart_top is
        generic (G_CLK_HZ : integer; G_BAUD : integer);
        port (
            i_clk       : in  std_logic;
            i_rst       : in  std_logic;
            i_adc_data  : in  std_logic_vector(7 downto 0);
            i_adc_valid : in  std_logic;
            o_tx_busy   : out std_logic;
            o_tx        : out std_logic
        );
    end component;

    -- Read one byte off the tx_line and return it
    procedure recv_byte (
        signal   line    : in  std_logic;
        variable result  : out std_logic_vector(7 downto 0)
    ) is
        variable b : std_logic_vector(7 downto 0);
    begin
        -- Wait for start bit (falling edge)
        wait until line = '0';
        -- Skip to middle of first data bit (1.5 bit periods from falling edge)
        wait for C_BIT_PERIOD + C_BIT_PERIOD / 2;
        for i in 0 to 7 loop
            b(i) := line;                  -- sample LSB first
            if i /= 7 then
                wait for C_BIT_PERIOD;
            end if;
        end loop;
        result := b;
    end procedure;

begin

    clk <= not clk after C_CLK_PERIOD / 2;

    u_dut : uart_top
        generic map (G_CLK_HZ => C_CLK_HZ, G_BAUD => C_BAUD)
        port map (
            i_clk       => clk,
            i_rst       => rst,
            i_adc_data  => adc_data,
            i_adc_valid => adc_valid,
            o_tx_busy   => tx_busy,
            o_tx        => tx_line
        );

    -- -------------------------------------------------------------------------
    -- ADC stimulus: send 8 bytes that look like real ADC readings
    -- -------------------------------------------------------------------------
    p_adc : process
        type t_bytes is array (0 to 7) of std_logic_vector(7 downto 0);
        constant DATA : t_bytes := (
            x"00", x"3F", x"7F", x"BF",   -- ramp up
            x"FF", x"BF", x"7F", x"3F"    -- ramp down
        );
    begin
        rst       <= '1';
        adc_valid <= '0';
        wait for C_CLK_PERIOD * 10;
        wait until rising_edge(clk);
        rst <= '0';
        wait for C_CLK_PERIOD * 5;

        for i in 0 to 7 loop
            -- Wait until TX is free
            if tx_busy = '1' then
                wait until tx_busy = '0';
            end if;
            wait until rising_edge(clk);
            adc_data  <= DATA(i);
            adc_valid <= '1';
            wait until rising_edge(clk);
            adc_valid <= '0';
        end loop;

        -- Wait for the last byte to finish
        wait until tx_busy = '0';
        report "All bytes sent";
        wait;
    end process;

    -- -------------------------------------------------------------------------
    -- Checker: sample the TX line and verify each byte
    -- -------------------------------------------------------------------------
    p_check : process
        type t_bytes is array (0 to 7) of std_logic_vector(7 downto 0);
        constant EXPECTED : t_bytes := (
            x"00", x"3F", x"7F", x"BF",
            x"FF", x"BF", x"7F", x"3F"
        );
        variable got : std_logic_vector(7 downto 0);
    begin
        wait until rst = '0';

        for i in 0 to 7 loop
            recv_byte(tx_line, got);
            if got = EXPECTED(i) then
                report "PASS byte " & integer'image(i) &
                       ": 0x" & integer'image(to_integer(unsigned(got)));
            else
                report "FAIL byte " & integer'image(i) &
                       ": expected 0x" &
                       integer'image(to_integer(unsigned(EXPECTED(i)))) &
                       " got 0x" &
                       integer'image(to_integer(unsigned(got)))
                    severity error;
            end if;
        end loop;

        report "=== Done ===" severity note;
        wait;
    end process;

end architecture;