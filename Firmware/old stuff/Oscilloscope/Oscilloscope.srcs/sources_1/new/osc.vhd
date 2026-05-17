library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity osc is
    Port (
        clk         : in  std_logic;
        uart_txd    : out std_logic;
        pwm_out     : out std_logic;
        vp_in       : in  std_logic;
        vn_in       : in  std_logic
    );
end osc;

architecture Behavioral of osc is

    component xadc_wiz_0
        port (
            di_in       : in  std_logic_vector(15 downto 0);
            daddr_in    : in  std_logic_vector(6 downto 0);
            den_in      : in  std_logic;
            dwe_in      : in  std_logic;
            drdy_out    : out std_logic;
            do_out      : out std_logic_vector(15 downto 0);
            dclk_in     : in  std_logic;
            reset_in    : in  std_logic;
            vp_in       : in  std_logic;
            vn_in       : in  std_logic;
            channel_out : out std_logic_vector(4 downto 0);
            eoc_out     : out std_logic;
            alarm_out   : out std_logic;
            eos_out     : out std_logic;
            busy_out    : out std_logic
        );
    end component;

    -- XADC signals
    signal eoc          : std_logic;
    signal drdy         : std_logic;
    signal xadc_data    : std_logic_vector(15 downto 0);
    signal sample       : unsigned(11 downto 0);
    signal sample_valid : std_logic;

    -- Math accumulator
    constant WINDOW      : integer := 256;
    constant WINDOW_LOG2 : integer := 8;

    signal count         : integer range 0 to WINDOW - 1 := 0;
    signal sum           : unsigned(19 downto 0) := (others => '0');
    signal min_val       : unsigned(11 downto 0) := (others => '1');
    signal max_val       : unsigned(11 downto 0) := (others => '0');
    signal prev_sample   : unsigned(11 downto 0) := (others => '0');
    signal zc_count      : unsigned(7 downto 0)  := (others => '0');

    signal result_mean   : unsigned(11 downto 0) := (others => '0');
    signal result_vpp    : unsigned(11 downto 0) := (others => '0');
    signal result_freq   : unsigned(15 downto 0) := (others => '0');
    signal window_done   : std_logic := '0';

    -- PWM
    -- 12-bit counter gives 4096 steps, runs at 100MHz/4096 = ~24 kHz
    -- easy to see on any oscilloscope
    signal pwm_counter   : unsigned(11 downto 0) := (others => '0');
    signal pwm_threshold : unsigned(11 downto 0) := (others => '0');

    -- Packet sender
    constant PKT_LEN    : integer := 7;
    type send_state_t is (IDLE, SEND_BYTE, WAIT_TX);
    signal send_state   : send_state_t := IDLE;
    signal byte_index   : integer range 0 to PKT_LEN - 1 := 0;
    signal tx_byte      : std_logic_vector(7 downto 0);
    signal tx_start     : std_logic := '0';
    signal tx_busy      : std_logic := '0';
    type pkt_t is array(0 to PKT_LEN - 1) of std_logic_vector(7 downto 0);
    signal packet       : pkt_t;

    -- UART TX
    constant CLK_FREQ     : integer := 100_000_000;
    constant BAUD_RATE    : integer := 115_200;
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;
    type uart_state_t is (U_IDLE, U_START, U_DATA, U_STOP);
    signal uart_state   : uart_state_t := U_IDLE;
    signal baud_cnt     : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index    : integer range 0 to 7 := 0;
    signal shift_reg    : std_logic_vector(7 downto 0);

begin

    -- XADC
    xadc_inst : xadc_wiz_0
        port map (
            dclk_in     => clk,
            reset_in    => '0',
            vp_in => vp_in,
            vn_in => vn_in,
            di_in       => (others => '0'),
            daddr_in    => (others => '0'),
            den_in      => eoc,
            dwe_in      => '0',
            drdy_out    => drdy,
            do_out      => xadc_data,
            channel_out => open,
            eoc_out     => eoc,
            alarm_out   => open,
            eos_out     => open,
            busy_out    => open
        );

    -- Sample capture
    process(clk)
    begin
        if rising_edge(clk) then
            sample_valid <= '0';
            if drdy = '1' then
                sample       <= unsigned(xadc_data(15 downto 4));
                sample_valid <= '1';
            end if;
        end if;
    end process;

    -- Math accumulator
    process(clk)
    begin
        if rising_edge(clk) then
            window_done <= '0';
            if sample_valid = '1' then
                sum <= sum + sample;
                if sample > max_val then max_val <= sample; end if;
                if sample < min_val then min_val <= sample; end if;
                if prev_sample < to_unsigned(2048, 12) and
                   sample      >= to_unsigned(2048, 12) then
                    zc_count <= zc_count + 1;
                end if;
                prev_sample <= sample;
                if count = WINDOW - 1 then
                    result_mean   <= sum(WINDOW_LOG2 + 11 downto WINDOW_LOG2);
                    result_vpp    <= max_val - min_val;
                    result_freq   <= resize(zc_count * to_unsigned(7, 4), 16);
                    window_done   <= '1';
                    count         <= 0;
                    sum           <= (others => '0');
                    min_val       <= (others => '1');
                    max_val       <= (others => '0');
                    zc_count      <= (others => '0');
                else
                    count <= count + 1;
                end if;
            end if;
        end if;
    end process;

    -- ----------------------------------------------------------------
    --  PWM output - duty cycle = result_mean / 4095
    --  Updates every window (every ~65ms)
    --  PWM frequency = 100MHz / 4096 = ~24 kHz
    -- ----------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            -- Latch new threshold when window completes
            if window_done = '1' then
                pwm_threshold <= result_mean;
            end if;

            -- Free-running 12-bit counter
            pwm_counter <= pwm_counter + 1;

            -- Output high when counter is below threshold
            if pwm_counter < pwm_threshold then
                pwm_out <= '1';
            else
                pwm_out <= '0';
            end if;
        end if;
    end process;

    -- Packet sender FSM
    process(clk)
    begin
        if rising_edge(clk) then
            tx_start <= '0';
            case send_state is
                when IDLE =>
                    if window_done = '1' then
                        packet(0) <= x"AB";
                        packet(1) <= std_logic_vector(resize(result_mean(11 downto 8), 8));
                        packet(2) <= std_logic_vector(result_mean(7 downto 0));
                        packet(3) <= std_logic_vector(resize(result_vpp(11 downto 8), 8));
                        packet(4) <= std_logic_vector(result_vpp(7 downto 0));
                        packet(5) <= std_logic_vector(result_freq(15 downto 8));
                        packet(6) <= std_logic_vector(result_freq(7 downto 0));
                        byte_index  <= 0;
                        send_state  <= SEND_BYTE;
                    end if;
                when SEND_BYTE =>
                    if tx_busy = '0' then
                        tx_byte    <= packet(byte_index);
                        tx_start   <= '1';
                        send_state <= WAIT_TX;
                    end if;
                when WAIT_TX =>
                    if tx_busy = '0' then
                        if byte_index = PKT_LEN - 1 then
                            send_state <= IDLE;
                        else
                            byte_index <= byte_index + 1;
                            send_state <= SEND_BYTE;
                        end if;
                    end if;
            end case;
        end if;
    end process;

    -- UART TX
    process(clk)
    begin
        if rising_edge(clk) then
            case uart_state is
                when U_IDLE =>
                    uart_txd <= '1';
                    tx_busy  <= '0';
                    if tx_start = '1' then
                        shift_reg  <= tx_byte;
                        baud_cnt   <= 0;
                        tx_busy    <= '1';
                        uart_state <= U_START;
                    end if;
                when U_START =>
                    uart_txd <= '0';
                    if baud_cnt = CLKS_PER_BIT - 1 then
                        baud_cnt   <= 0;
                        bit_index  <= 0;
                        uart_state <= U_DATA;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;
                when U_DATA =>
                    uart_txd <= shift_reg(bit_index);
                    if baud_cnt = CLKS_PER_BIT - 1 then
                        baud_cnt <= 0;
                        if bit_index = 7 then
                            uart_state <= U_STOP;
                        else
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;
                when U_STOP =>
                    uart_txd <= '1';
                    if baud_cnt = CLKS_PER_BIT - 1 then
                        baud_cnt   <= 0;
                        tx_busy    <= '0';
                        uart_state <= U_IDLE;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;
            end case;
        end if;
    end process;

end Behavioral;