----------------------------------------------------------------------------------
-- shit
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity trigger_struct is
port (
    t_clk         : in  std_logic;
    t_reset       : in  std_logic;

    -- trigger settings
    i_trig_level  : in std_logic_vector(15 downto 0);
    i_trig_type   : in std_logic;
    arm_trigger   : in std_logic;

    -- trigger outputs
    o_buffer      : out std_logic_vector(7 downto 0);
    o_trig_good   : out std_logic;
    i_read_req    : in  std_logic;

    -- adc stuff
    i_adc_data    : in std_logic_vector(15 downto 0);
    i_adc_valid   : in std_logic;
    i_dec_factor  : in std_logic_vector(7 downto 0)

);
end trigger_struct;

architecture Structural of trigger_struct is

    signal o_dec_output : std_logic_vector(15 downto 0);
    signal dec_reg      : std_logic_vector(15 downto 0);
    signal byte_sel     : std_logic := '0';
    signal data_valid   : std_logic := '0';

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

begin
    u_decimator : decimator
    port map (
        d_clk => t_clk,
        d_reset => t_reset,
        i_adc_valid => i_adc_valid,
        i_adc_in => i_adc_data,
        i_dec_factor => i_dec_factor,
        o_dec_output => o_dec_output
    );
    
    process(t_clk)
    begin
        if rising_edge(t_clk) then
            if t_reset = '1' then
                byte_sel <= '0';
                data_valid <= '0';
            else
                if i_adc_valid = '1' then
                    dec_reg <= o_dec_output;
                    byte_sel <= '0';
                    data_valid <= '1';
                elsif i_read_req = '1' and data_valid = '1' then
                    if byte_sel = '0' then
                        byte_sel <= '1';
                    else
                        data_valid <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    o_buffer <= dec_reg(15 downto 8) when byte_sel = '0' else dec_reg(7 downto 0);
    o_trig_good <= data_valid;

end Structural;
