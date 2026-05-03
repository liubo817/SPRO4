----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/24/2026 03:38:14 PM
-- Design Name: 
-- Module Name: tb_decimator - Behavioral
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

entity tb_decimator is
--  Port ( );
end tb_decimator;

architecture Behavioral of tb_decimator is

    component decimator is 
        port (
            d_clk : in std_logic;
            d_reset : in std_logic;

            i_adc_valid : in std_logic;
            i_adc_in : in std_logic_vector(15 downto 0);

            i_dec_factor : in std_logic_vector(7 downto 0);
            o_dec_output : out std_logic_vector(15 downto 0)
        );
    end component;
    
    constant CLK_PERIOD : time := 10 ns;
     
     -- Clock and Reset
    signal tb_clk        : std_logic := '0';
    signal tb_reset      : std_logic := '1';

    -- Data Inputs
    signal tb_adc_valid  : std_logic := '0';
    signal tb_adc_in     : std_logic_vector(15 downto 0) := (others => '0');
    signal tb_dec_factor : std_logic_vector(7 downto 0)  := x"02"; -- Example factor of 2

    -- Data Outputs
    signal tb_dec_output : std_logic_vector(15 downto 0);

begin
    DUT_DECIMATOR : decimator
    port map (
        d_clk        => tb_clk,
        d_reset      => tb_reset,
        i_adc_valid  => tb_adc_valid,
        i_adc_in     => tb_adc_in,
        i_dec_factor => tb_dec_factor,
        o_dec_output => tb_dec_output
    );
    
    tb_clk <= not tb_clk after CLK_PERIOD / 2;
    
    process
    begin		
        -- Initial Reset
        tb_reset <= '1';
        wait for 20 ns;
        tb_reset <= '0';
        wait for clk_period * 2;

        -- Set Decimation Factor (e.g., Decimate by 4)
        tb_dec_factor <= x"02"; 
        
        -- Feed Data: Input '8' consistently 
        -- If decimation factor is 4, it should accumulate 8+8+8+8 = 32, 
        -- then shift right by 4 (divide by 16) = result 2.
        tb_adc_valid <= '1';
        for i in 1 to 16 loop
            -- Multiply the loop index by 10 to create a ramp
            tb_adc_in <= std_logic_vector(to_unsigned(i * 10, 16)); 
            wait for clk_period;
        end loop;

        -- Stop valid data
        tb_adc_valid <= '0';
        
        wait for 100 ns;
        assert false report "Simulation Finished" severity failure;
        wait;
    end process;
    
end Behavioral;
