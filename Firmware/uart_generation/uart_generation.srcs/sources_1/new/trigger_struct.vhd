----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/18/2026 08:36:30 PM
-- Design Name: 
-- Module Name: trigger_struct - Structural
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

end Structural;
