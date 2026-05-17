library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_osc is
end tb_osc;

architecture sim of tb_osc is
    signal clk      : std_logic := '0';
    signal uart_txd : std_logic;
    signal pwm_out  : std_logic;
    signal vp_in    : std_logic := '0';
    signal vn_in    : std_logic := '0';
    
    constant clk_period : time := 10 ns; -- 100 MHz
begin
    -- Instantiate the design
    uut: entity work.osc
        port map (
            clk      => clk,
            uart_txd => uart_txd,
            pwm_out  => pwm_out,
            vp_in    => vp_in,
            vn_in    => vn_in
        );

    -- Clock generator
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- Stimulus: In a real simulation, we'd need a XADC stimulus file,
    -- but for now, this will at least get the clock and PWM running.
    stim_proc: process
    begin		
        wait for 100 ns;
        -- You can add signal toggling here if you want to test UART response
        wait;
    end process;

end sim;