-- =============================================================================
-- osc.vhd  --  Oscilloscope Top Level
-- Connects wave_generator and uart_top
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity osc is
    generic (
        G_CLK_HZ  : integer := 100_000_000;
        G_BAUD    : integer := 115_200;
        CLK_DIV_N : integer := 256
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        -- FTDI UART pins
        i_rx        : in  std_logic;
        o_tx        : out std_logic;
        -- ADC input
        -- i_adc_data  : in  std_logic_vector(7 downto 0);
        o_tx_busy   : out std_logic;
        vp_in       : in  std_logic;
        vn_in       : in  std_logic;
        -- Wave output
        pwm_out     : out std_logic;
        saw_out     : out std_logic_vector(7 downto 0)
    );
end entity;

architecture Structural of osc is

    component uart_top is
        generic (G_CLK_HZ : integer; G_BAUD : integer);
        port (
            i_clk       : in  std_logic;
            i_rst       : in  std_logic;
            i_tx_data   : in  std_logic_vector(7 downto 0);
            i_adc_valid : in  std_logic;
            o_tx_busy   : out std_logic;
            o_tx        : out std_logic;
            i_rx        : in  std_logic;
            o_duty      : out std_logic_vector(7 downto 0);
            o_wave_sel  : out std_logic;
            o_trig_type : out std_logic;
            o_trig_level : out std_logic_vector(15 downto 0);
            o_dec_factor : out std_logic_vector(7 downto 0);
            o_arm_trig : out std_logic;
            i_trig_good : in std_logic;
            o_read_req : out std_logic
        );
    end component;

    signal eoc          : std_logic;
    signal drdy         : std_logic;
    signal xadc_data    : std_logic_vector(15 downto 0); -- We only strictly need what we use, but let's keep your mapping
    signal xadc_out     : std_logic_vector(15 downto 0);
    signal i_tx_data    : std_logic_vector(7 downto 0);
    signal trig_level   : std_logic_vector(15 downto 0);
    signal trig_type    : std_logic;
    signal trig_good    : std_logic;
    signal read_req     : std_logic;
    signal dec_factor   : std_logic_vector(7 downto 0);
    signal arm_trigger  : std_logic;
    
    component xadc_wiz_0
        port (
            dclk_in     : in  std_logic;
            reset_in    : in  std_logic;
            di_in       : in  std_logic_vector(15 downto 0);
            daddr_in    : in  std_logic_vector(6 downto 0);
            den_in      : in  std_logic;
            dwe_in      : in  std_logic;
            drdy_out    : out std_logic;
            do_out      : out std_logic_vector(15 downto 0);
            vp_in       : in  std_logic;
            vn_in       : in  std_logic;
            eoc_out     : out std_logic;
            channel_out : out std_logic_vector(4 downto 0);
            alarm_out   : out std_logic;
            eos_out     : out std_logic;
            busy_out    : out std_logic
        );
    end component;

    component wave_generator is
        generic (CLK_DIV_N : integer);
        port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            duty     : in  std_logic_vector(7 downto 0);
            wave_sel : in  std_logic;
            pwm_out  : out std_logic;
            saw_out  : out std_logic_vector(7 downto 0)
        );
    end component;

    component trigger_struct is
        port (
            t_clk         : in  std_logic;
            t_reset       : in  std_logic;
            i_trig_level  : in std_logic_vector(15 downto 0);
            i_trig_type   : in std_logic;
            arm_trigger   : in std_logic;
            o_buffer      : out std_logic_vector(7 downto 0);
            o_trig_good   : out std_logic;
            i_read_req    : in  std_logic;
            i_adc_data    : in std_logic_vector(15 downto 0);
            i_adc_valid   : in std_logic;
            i_dec_factor  : in std_logic_vector(7 downto 0)
        );

    end component;

    -- Internal wires between uart_top and wave_generator
    signal duty_sig     : std_logic_vector(7 downto 0);
    signal wave_sel_sig : std_logic;
begin

    u_uart : uart_top
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_BAUD   => G_BAUD
        )
        port map (
            i_clk       => clk,
            i_rst       => reset,
            o_tx_busy   => o_tx_busy,
            i_adc_valid => drdy,
            i_tx_data   => i_tx_data,
            o_tx        => o_tx,
            i_rx        => i_rx,
            o_duty      => duty_sig,
            o_wave_sel  => wave_sel_sig,
            o_trig_type => trig_type,
            o_trig_level => trig_level,
            o_dec_factor => dec_factor,
            o_arm_trig => arm_trigger,
            i_trig_good => trig_good,
            o_read_req => read_req
        );
        
    xadc_inst : xadc_wiz_0
        port map (
            dclk_in     => clk,
            reset_in    => '0',
            di_in       => (others => '0'),
            daddr_in    => "0000011", -- Address 0x00: Internal Temperature
            den_in      => eoc,       -- Auto-trigger
            dwe_in      => '0',
            drdy_out    => drdy,
            do_out      => xadc_out,
            vp_in       => vp_in,
            vn_in       => vn_in,
            eoc_out     => eoc,
            channel_out => open,
            alarm_out   => open,
            eos_out     => open,
            busy_out    => open
        );

    u_trigger : trigger_struct
        port map (
            t_clk   => clk,
            t_reset => reset,
            i_trig_level => trig_level,
            i_trig_type => trig_type,
            o_buffer => i_tx_data,
            o_trig_good => trig_good,
            i_read_req  => read_req,
            i_adc_data  => xadc_data,
            i_adc_valid => drdy,
            i_dec_factor => dec_factor,
            arm_trigger => arm_trigger
        );

    u_wave : wave_generator
        generic map (
            CLK_DIV_N => CLK_DIV_N
        )
        port map (
            clk      => clk,
            reset    => reset,
            duty     => duty_sig,
            wave_sel => wave_sel_sig,
            pwm_out  => pwm_out,
            saw_out  => saw_out
        );

end architecture;