----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/18/2026 11:19:45 PM
-- Design Name: 
-- Module Name: decimator - Behavioral
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

entity decimator is
    Port (
        d_clk : in std_logic;
        d_reset : in std_logic;

        i_adc_valid : in std_logic;
        i_adc_in : in std_logic_vector(15 downto 0);

        i_dec_factor : in std_logic_vector(7 downto 0);
        o_dec_valid : out std_logic;
        o_dec_output : out std_logic_vector(15 downto 0)


    );
end decimator;

architecture Behavioral of decimator is

    signal accu_register : unsigned(23 downto 0) := (others => '0'); -- 24-bit so it doesn't overflow
    signal counter       : unsigned(7 downto 0)  := (others => '0');

begin
    process(d_clk)
        variable accu_next : unsigned(23 downto 0);  -- variable: updates immediately
        variable shifted_result : unsigned(23 downto 0); -- stores a shift left by 4, because 
        
    begin
        if rising_edge(d_clk) then
            if d_reset = '1' then
                counter       <= (others => '0');
                o_dec_valid   <= '0';
                accu_register <= (others => '0');
                o_dec_output  <= (others => '0');
            else
                o_dec_valid <= '0';
                if i_adc_valid = '1' then
                    accu_next := accu_register + unsigned(i_adc_in(15 downto 4));  -- immediate
                    shifted_result := shift_right(accu_next, to_integer(unsigned(i_dec_factor)));

                    if counter >= (shift_left(to_unsigned(1, counter'length), 
                                   to_integer(unsigned(i_dec_factor))) - 1) then
                        -- accu_next already includes the final sample
                        o_dec_output  <= std_logic_vector(shifted_result(15 downto 0));
                        o_dec_valid   <= '1';
                        accu_register <= (others => '0');
                        counter       <= (others => '0');
                    else
                        accu_register <= accu_next;
                        counter       <= counter + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
