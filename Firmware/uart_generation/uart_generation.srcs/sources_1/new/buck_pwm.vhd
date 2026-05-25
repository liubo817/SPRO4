library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PWM_generator is
    Generic (
        CLK_FREQ_HZ  : integer := 100_000_000;
        PWM_FREQ_HZ  : integer := 15_000;    -- change this: 10000–20000
        DUTY_PERCENT : integer := 50         -- change this: 0–100
    );
    Port (
        clk     : in  STD_LOGIC;
        reset   : in  STD_LOGIC;
        buck_out : out STD_LOGIC
    );
end PWM_generator;

architecture Behavioral of PWM_generator is

    constant DIV_VAL : integer := CLK_FREQ_HZ / (PWM_FREQ_HZ * 256);
    constant DUTY_8BIT : unsigned(7 downto 0) := 
        to_unsigned((DUTY_PERCENT * 256) / 100, 8);

    signal div_counter : integer range 0 to DIV_VAL := 0;
    signal clk_en      : STD_LOGIC := '0';
    signal counter     : unsigned(7 downto 0) := (others => '0');

begin

    p_clk_en : process(clk)
    begin
        if rising_edge(clk) then
            clk_en <= '0';
            if reset = '1' then
                div_counter <= 0;
            elsif div_counter >= DIV_VAL - 1 then
                clk_en      <= '1';
                div_counter <= 0;
            else
                div_counter <= div_counter + 1;
            end if;
        end if;
    end process;

    p_counter : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter <= (others => '0');
            elsif clk_en = '1' then
                counter <= counter + 1;
            end if;
        end if;
    end process;

    p_outputs : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                buck_out <= '0';
            elsif counter < DUTY_8BIT then
                buck_out <= '1';
            else
                buck_out <= '0';
            end if;
        end if;
    end process;

end Behavioral;