----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/01/2026 04:52:51 PM
-- Design Name: 
-- Module Name: uart_main - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity uart_main is
    generic (
        baud                : positive := 115200;
        clock_frequency     : positive := 100000000
    );
    port (  
        clock                   :   in      std_logic;
        user_reset              :   in      std_logic;    
        rx_top           :   in      std_logic;
        tx_top           :   out     std_logic
    );
end uart_main;

architecture rtl of uart_main is
    component loopback is
        generic (
            baud                : positive;
            clock_frequency     : positive
        );
        port(  
            clock                   :   in      std_logic;
            reset                   :   in      std_logic;    
            rx                      :   in      std_logic;
            tx                      :   out     std_logic
        );
    end component loopback;
    signal tx, rx, rx_sync, reset, reset_sync : std_logic;
begin
    ----------------------------------------------------------------------------
    -- Loopback instantiation
    ----------------------------------------------------------------------------
    loopback_inst1 : loopback
    generic map (
        baud                => baud,
        clock_frequency     => clock_frequency
    )
    port map (  
        clock       => clock,
        reset       => reset, 
        rx          => rx,
        tx          => tx
    );
    ----------------------------------------------------------------------------
    -- Deglitch inputs
    ----------------------------------------------------------------------------
    deglitch : process (clock)
    begin
        if rising_edge(clock) then
            rx_sync         <= rx_top;
            rx              <= rx_sync;
            reset_sync      <= user_reset;
            reset           <= reset_sync;
            tx_top   <= tx;
        end if;
    end process;
end rtl;
