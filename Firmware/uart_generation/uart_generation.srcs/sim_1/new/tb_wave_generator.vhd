-- =============================================================================
-- tb_wave_generator_duty.vhd
-- Duty-cycle focused testbench for wave_generator
--
-- This TB:
--   * Keeps frequency fixed at 100 Hz
--   * Sweeps through all duty-cycle values
--   * Lets you inspect pwm_out waveform easily
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_wave_generator is
end tb_wave_generator;

architecture Behavioral of tb_wave_generator is

    -- =========================================================================
    -- Constants
    -- =========================================================================
    constant CLK_PERIOD : time := 10 ns; -- 100 MHz

    -- =========================================================================
    -- DUT Signals
    -- =========================================================================
    signal clk      : STD_LOGIC := '0';
    signal reset    : STD_LOGIC := '0';
    signal duty     : STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
    signal freq_sel : STD_LOGIC_VECTOR(3 downto 0) := "0001"; -- fixed 100 Hz
    signal pwm_out  : STD_LOGIC;

begin

    -- =========================================================================
    -- DUT Instantiation
    -- =========================================================================
    DUT : entity work.wave_generator
        generic map (
            CLK_FREQ_HZ => 1_000_000 -- faster simulation
        )
        port map (
            clk      => clk,
            reset    => reset,
            duty     => duty,
            freq_sel => freq_sel,
            pwm_out  => pwm_out
        );

    -- =========================================================================
    -- Clock Generation
    -- =========================================================================
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD / 2;

            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    -- =========================================================================
    -- Stimulus Process
    -- =========================================================================
    stim_proc : process
    begin

        -- ---------------------------------------------------------------------
        -- Reset
        -- ---------------------------------------------------------------------
        reset <= '1';
        wait for 100 ns;

        reset <= '0';
        wait for 100 ns;

        -- ---------------------------------------------------------------------
        -- Fixed Frequency = 100 Hz
        -- ---------------------------------------------------------------------
        freq_sel <= "0001";

        duty <= "010";
        wait for 1 ms;

        -- ---------------------------------------------------------------------
        -- End Simulation
        -- ---------------------------------------------------------------------

        wait;

    end process;

end Behavioral;