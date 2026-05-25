-- =============================================================================
-- osc.vhd  --  Oscilloscope Top Level (FIXED)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity osc is
    generic (
        G_CLK_HZ  : integer := 100_000_000;
        G_BAUD    : integer := 115_200
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;

        -- UART
        i_rx        : in  std_logic;
        o_tx        : out std_logic;
        o_tx_busy   : out std_logic;

        -- XADC
        vp_in       : in  std_logic;
        vn_in       : in  std_logic;
        
        -- debug LED
        led : out std_logic;
        
        led2 : out std_logic;
        led3 : out std_logic;
        led4 : out std_logic;
        led5 : out std_logic;

        -- Wave outputs
        pwm_out     : out std_logic;
        buck_out    : out std_logic
    );
end entity;

architecture Structural of osc is

    -------------------------------------------------------------------------
    -- UART TOP (MATCHES YOUR LATEST FILE)
    -------------------------------------------------------------------------
    component uart_top is
        generic (
            G_CLK_HZ : integer;
            G_BAUD   : integer
        );
        port (
            i_clk        : in  std_logic;
            i_rst        : in  std_logic;

            i_tx_data    : in  std_logic_vector(7 downto 0);
            i_adc_valid  : in  std_logic;
            
            o_trig_level : out std_logic_vector(15 downto 0);
            o_trig_type  : out std_logic;
            o_dec_factor : out std_logic_vector(7 downto 0);
            o_arm_trig   : out std_logic;

            o_tx_busy    : out std_logic;
            o_tx         : out std_logic;
            i_rx         : in  std_logic;
            
            o_led : out std_logic;

            o_duty       : out std_logic_vector(3 downto 0);
            o_freq_sel   : out std_logic_vector(3 downto 0);

            i_trig_good  : in  std_logic;
            o_read_req   : out std_logic
            
            
        );
    end component;

    -------------------------------------------------------------------------
    -- XADC
    -------------------------------------------------------------------------
    component xadc_wiz_0
        port (
            dclk_in     : in  std_logic; -- digital clock input
            reset_in    : in  std_logic; -- what do you think?
            di_in       : in  std_logic_vector(15 downto 0); -- drp data in
            daddr_in    : in  std_logic_vector(6 downto 0); -- drp address. this is how you choose the read address (temp or external or voltage reg etc)
            den_in      : in  std_logic; -- drp enable. pulse to activate comm
            dwe_in      : in  std_logic; -- drp write enable. low to read high to write
            drdy_out    : out std_logic; -- drp ready. tells you if a read is ready
            do_out      : out std_logic_vector(15 downto 0); -- data out
            vp_in       : in  std_logic; -- adc input pos
            vn_in       : in  std_logic; -- adc input neg
            eoc_out     : out std_logic; -- pulses when an adc conversion is done
            channel_out : out std_logic_vector(4 downto 0); -- output what channel is used
            alarm_out   : out std_logic; -- high is an alarm triggers (e.g. overvoltage)
            eos_out     : out std_logic; -- end of seq (not used?)
            busy_out    : out std_logic -- adc busy
        );
    end component;

    -------------------------------------------------------------------------
    -- Wave generator (MATCHES YOUR UPDATED VERSION)
    -------------------------------------------------------------------------
    component wave_generator is
        generic (
            CLK_FREQ_HZ : integer := 100_000_000
        );
        port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            duty     : in  std_logic_vector(3 downto 0);
            freq_sel : in  std_logic_vector(3 downto 0);
            pwm_out  : out std_logic
        );
    end component;
    
    component PWM_generator is
        generic (
            CLK_FREQ_HZ  : integer := 100_000_000;
            PWM_FREQ_HZ  : integer := 15_000;    -- change this: 10000-20000
            DUTY_PERCENT : integer := 50
        );
        port (
            clk     : in  STD_LOGIC;
            reset   : in  STD_LOGIC;
            buck_out : out STD_LOGIC
        );
    end component;

    -------------------------------------------------------------------------
    -- Trigger
    -------------------------------------------------------------------------
    component trigger_struct is
        port (
            t_clk         : in  std_logic;
            t_reset       : in  std_logic;

            i_trig_level  : in  std_logic_vector(15 downto 0);
            i_trig_type   : in  std_logic;
            arm_trigger   : in  std_logic;

            o_buffer      : out std_logic_vector(7 downto 0);
            o_trig_good   : out std_logic;

            i_read_req    : in  std_logic;

            i_adc_data    : in  std_logic_vector(15 downto 0);
            i_adc_valid   : in  std_logic;

            i_dec_factor  : in  std_logic_vector(7 downto 0);
            
            o_led2 : out std_logic;
            o_led3 : out std_logic;
            o_led4 : out std_logic;
            o_led5 : out std_logic
        );
    end component;

    -------------------------------------------------------------------------
    -- Signals
    -------------------------------------------------------------------------
    signal eoc          : std_logic;
    signal drdy         : std_logic;

    signal xadc_out     : std_logic_vector(15 downto 0);
    signal xadc_data    : std_logic_vector(15 downto 0);

    signal i_tx_data    : std_logic_vector(7 downto 0);

    signal trig_level   : std_logic_vector(15 downto 0);
    signal trig_type    : std_logic;

    signal trig_good    : std_logic;
    signal read_req     : std_logic;

    signal dec_factor   : std_logic_vector(7 downto 0);
    signal arm_trigger  : std_logic;

    signal duty_sig     : std_logic_vector(3 downto 0);
    signal freq_sel_sig : std_logic_vector(3 downto 0);

begin

    -------------------------------------------------------------------------
    -- XADC wiring
    -------------------------------------------------------------------------
    xadc_data <= xadc_out;

    xadc_inst : xadc_wiz_0
        port map (
            dclk_in     => clk,
            reset_in    => '0',

            di_in       => (others => '0'), -- no data in
            daddr_in    => "0000011", -- read address

            den_in      => eoc, -- pulses itself basically
            dwe_in      => '0', -- we're not doing any writes

            drdy_out    => drdy, -- read ready
            do_out      => xadc_out, -- whaddya think

            vp_in       => vp_in, -- yes
            vn_in       => vn_in, -- yes

            eoc_out     => eoc, -- end of conversion

            channel_out => open, -- we're only using one channel
            alarm_out   => open, -- we have no alarms
            eos_out     => open, -- we are not using cycles
            busy_out    => open -- wedon'tgaf
        );

    -------------------------------------------------------------------------
    -- UART
    -------------------------------------------------------------------------
    u_uart : uart_top
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_BAUD   => G_BAUD
        )
        port map (
            i_clk        => clk,
            i_rst        => reset,

            i_tx_data    => i_tx_data,
            i_adc_valid  => drdy,
            o_trig_level => trig_level,
            o_trig_type  => trig_type,
            o_dec_factor => dec_factor,
            o_arm_trig   => arm_trigger,

            o_tx_busy    => o_tx_busy,
            o_tx         => o_tx,
            i_rx         => i_rx,

            o_duty       => duty_sig,
            o_freq_sel   => freq_sel_sig,

            i_trig_good  => trig_good,
            o_led => led,
            o_read_req   => read_req
        );

    -------------------------------------------------------------------------
    -- Trigger
    -------------------------------------------------------------------------
    u_trigger : trigger_struct
        port map (
            t_clk         => clk,
            t_reset       => reset,

            i_trig_level  => trig_level,
            i_trig_type   => trig_type,
            arm_trigger   => arm_trigger,

            o_buffer      => i_tx_data,
            o_trig_good   => trig_good,

            i_read_req    => read_req,

            i_adc_data    => xadc_data,
            i_adc_valid   => drdy,

            i_dec_factor  => dec_factor,
            
            o_led2 => led2,
            o_led3 => led3,
            o_led4 => led4,
            o_led5 => led5
            );
            
    -------------------------------------------------------------------------
    -- Buck PWM generator
    -------------------------------------------------------------------------
    u_buck_pwm : PWM_generator
        generic map (
            CLK_FREQ_HZ => G_CLK_HZ
        )
        port map (
            clk      => clk,
            reset    => reset,
            buck_out => buck_out
        );

    -------------------------------------------------------------------------
    -- Wave generator
    -------------------------------------------------------------------------
    u_wave : wave_generator
        generic map (
            CLK_FREQ_HZ => G_CLK_HZ
        )
        port map (
            clk      => clk,
            reset    => reset,
            duty     => duty_sig,
            freq_sel => freq_sel_sig,
            pwm_out  => pwm_out
        );

end architecture;