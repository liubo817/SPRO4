----------------------------------------------------------------------------------
-- decimator.vhd
-- Trigger submodule to "decimate" data, using a moving average window
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity decimator is
    Port (
        d_clk : in std_logic; -- clock
        d_reset : in std_logic; -- reset

        i_adc_valid : in std_logic; -- signal for new adc data
        i_adc_in : in std_logic_vector(15 downto 0); -- adc input bus

        i_dec_factor : in std_logic_vector(7 downto 0); -- factor control
        o_dec_valid : out std_logic; -- signal for when data is ready
        o_dec_output : out std_logic_vector(15 downto 0) -- output bus
    );
end decimator;

architecture Behavioral of decimator is

    signal accu_register : unsigned(23 downto 0) := (others => '0'); -- 24-bit so it doesn't overflow until 9-10
    signal counter       : unsigned(7 downto 0)  := (others => '0');

begin
    process(d_clk)
        variable accu_next : unsigned(23 downto 0);
        variable shifted_result : unsigned(23 downto 0);
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
