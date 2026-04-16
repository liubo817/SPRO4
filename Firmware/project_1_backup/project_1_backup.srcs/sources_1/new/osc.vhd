library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity osc is
    Port (
        clk         : in  std_logic;
        uart_txd    : out std_logic;
        pwm_out     : out std_logic;
        leds        : out std_logic_vector(7 downto 0); -- LD0-LD7 for visual check
        vp_in       : in  std_logic;
        vn_in       : in  std_logic
    );
end osc;

architecture Behavioral of osc is

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

    signal eoc          : std_logic;
    signal drdy         : std_logic;
    signal xadc_data    : std_logic_vector(15 downto 10); -- We only strictly need what we use, but let's keep your mapping
    signal xadc_full    : std_logic_vector(15 downto 0);
    signal sample       : unsigned(11 downto 0);
    signal sample_valid : std_logic;

    -- Math / Averaging
    constant WINDOW      : integer := 256;
    constant WINDOW_LOG2 : integer := 8;
    signal count         : integer range 0 to WINDOW - 1 := 0;
    signal sum           : unsigned(19 downto 0) := (others => '0');
    signal result_mean   : unsigned(11 downto 0) := (others => '0');
    signal window_done   : std_logic := '0';

    -- PWM
    signal pwm_counter   : unsigned(11 downto 0) := (others => '0');
    signal pwm_threshold : unsigned(11 downto 0) := (others => '0');

    -- UART Setup
    constant CLK_FREQ     : integer := 100_000_000;
    constant BAUD_RATE    : integer := 115_200;
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;
    
    -- Expanded state machine for Multi-Byte transmission
    type uart_state_t is (U_IDLE, U_LOAD, U_START, U_DATA, U_STOP, U_NEXT_BYTE);
    signal uart_state   : uart_state_t := U_IDLE;
    signal baud_cnt     : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index    : integer range 0 to 7 := 0;
    signal tx_byte      : std_logic_vector(7 downto 0);
    
    -- Buffer for our ASCII characters: 3 Hex digits + CR + LF = 5 bytes
    type tx_buffer_t is array (0 to 4) of std_logic_vector(7 downto 0);
    signal tx_buffer     : tx_buffer_t;
    signal bytes_to_send : integer range 0 to 5 := 0;
    signal current_byte  : integer range 0 to 4 := 0;

begin

    -- XADC Instance configured for Internal Temperature (Addr 0x00)
    xadc_inst : xadc_wiz_0
        port map (
            dclk_in     => clk,
            reset_in    => '0',
            di_in       => (others => '0'),
            daddr_in    => "0000000", -- Address 0x00: Internal Temperature
            den_in      => eoc,       -- Auto-trigger
            dwe_in      => '0',
            drdy_out    => drdy,
            do_out      => xadc_full,
            vp_in       => vp_in,
            vn_in       => vn_in,
            eoc_out     => eoc,
            channel_out => open,
            alarm_out   => open,
            eos_out     => open,
            busy_out    => open
        );

    -- ADC Data Handoff and LED feedback
    process(clk)
    begin
        if rising_edge(clk) then
            sample_valid <= '0';
            if drdy = '1' then
                sample       <= unsigned(xadc_full(15 downto 4));
                leds         <= xadc_full(15 downto 8); -- Live temperature on LEDs
                sample_valid <= '1';
            end if;
        end if;
    end process;

    -- Math Accumulator
    process(clk)
    begin
        if rising_edge(clk) then
            window_done <= '0';
            if sample_valid = '1' then
                sum <= sum + sample;
                if count = WINDOW - 1 then
                    result_mean <= sum(WINDOW_LOG2 + 11 downto WINDOW_LOG2);
                    window_done <= '1';
                    count       <= 0;
                    sum         <= (others => '0');
                else
                    count <= count + 1;
                end if;
            end if;
        end if;
    end process;

    -- PWM Generator
    process(clk)
    begin
        if rising_edge(clk) then
            if window_done = '1' then
                pwm_threshold <= result_mean; -- PWM duty cycle follows Temp
            end if;
            pwm_counter <= pwm_counter + 1;
            if pwm_counter < pwm_threshold then
                pwm_out <= '1';
            else
                pwm_out <= '0';
            end if;
        end if;
    end process;

    -- UART Multi-byte Transmitter (Sends 12-bit Hex + CR + LF)
    process(clk)
        variable n2, n1, n0 : unsigned(3 downto 0);
    begin
        if rising_edge(clk) then
            case uart_state is
                when U_IDLE =>
                    uart_txd <= '1';
                    if window_done = '1' then
                        -- Extract the three 4-bit nibbles from the 12-bit result
                        n2 := result_mean(11 downto 8);
                        n1 := result_mean(7 downto 4);
                        n0 := result_mean(3 downto 0);

                        -- Convert Nibble 2 to ASCII
                        if n2 < 10 then tx_buffer(0) <= std_logic_vector(resize(n2, 8) + 48); -- '0'-'9'
                        else            tx_buffer(0) <= std_logic_vector(resize(n2, 8) + 55); end if; -- 'A'-'F'

                        -- Convert Nibble 1 to ASCII
                        if n1 < 10 then tx_buffer(1) <= std_logic_vector(resize(n1, 8) + 48);
                        else            tx_buffer(1) <= std_logic_vector(resize(n1, 8) + 55); end if;

                        -- Convert Nibble 0 to ASCII
                        if n0 < 10 then tx_buffer(2) <= std_logic_vector(resize(n0, 8) + 48);
                        else            tx_buffer(2) <= std_logic_vector(resize(n0, 8) + 55); end if;

                        -- Add Carriage Return (CR) and Line Feed (LF)
                        tx_buffer(3) <= x"0D";
                        tx_buffer(4) <= x"0A";

                        bytes_to_send <= 5;
                        current_byte  <= 0;
                        uart_state    <= U_LOAD;
                    end if;

                when U_LOAD =>
                    -- Give the buffer 1 clock cycle to settle, then load the byte
                    tx_byte    <= tx_buffer(current_byte);
                    baud_cnt   <= 0;
                    uart_state <= U_START;

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
                    uart_txd <= tx_byte(bit_index);
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
                        uart_state <= U_NEXT_BYTE;
                    else 
                        baud_cnt <= baud_cnt + 1; 
                    end if;

                when U_NEXT_BYTE =>
                    -- Check if we are done sending all 5 characters
                    if current_byte = bytes_to_send - 1 then
                        uart_state <= U_IDLE;
                    else
                        current_byte <= current_byte + 1;
                        uart_state   <= U_LOAD;
                    end if;

            end case;
        end if;
    end process;

end Behavioral;