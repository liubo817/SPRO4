-- =============================================================================
-- uart_top.vhd  --  TX sends ADC data, RX receives duty/wave_sel commands
-- Protocol: Python sends 2 bytes: byte[0]=duty, byte[1]=wave_sel (0x00 or 0x01)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_top is
    generic (
        G_CLK_HZ : integer := 100_000_000;
        G_BAUD   : integer := 115_200
    );
    port (
        i_clk        : in  std_logic;
        i_rst        : in  std_logic;
        -- ADC side (transit)
        i_tx_data    : in  std_logic_vector(7 downto 0);
        i_adc_valid  : in  std_logic;
        o_tx_busy    : out std_logic;
        o_tx         : out std_logic;
        -- FTDI receive
        i_rx         : in  std_logic;
        -- Wave generator control stuff
        o_duty       : out std_logic_vector(7 downto 0);
        o_wave_sel   : out std_logic;
        -- Trigger signals
        o_trig_type  : out std_logic;
        o_trig_level : out std_logic_vector(15 downto 0);
        o_dec_factor : out std_logic_vector(7 downto 0);
        o_arm_trig   : out std_logic;
        i_trig_good  : in  std_logic;
        o_read_req   : out std_logic
    );
end entity;

architecture Structural of uart_top is

    component uart_tx is
        generic (G_CLK_HZ : integer; G_BAUD : integer);
        port (
            i_clk   : in  std_logic;
            i_rst   : in  std_logic;
            i_data  : in  std_logic_vector(7 downto 0);
            i_valid : in  std_logic;
            o_busy  : out std_logic;
            o_tx    : out std_logic
        );
    end component;

    component uart_rx is
        generic (G_CLK_HZ : integer; G_BAUD : integer);
        port (
            i_clk   : in  std_logic;
            i_rst   : in  std_logic;
            i_rx    : in  std_logic;
            o_data  : out std_logic_vector(7 downto 0);
            o_valid : out std_logic
        );
    end component;

    signal rx_data  : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;

    -- Tracks whether next byte is duty or wave_sel
    signal rx_state : std_logic := '0'; -- '0' = wait for cmd, '1' = wait for data
    signal cmd_reg  : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Add a generic for how many bytes make up one oscilloscope "frame"
    -- (You can add this to your entity generics: G_FRAME_SIZE : integer := 1024;)
    constant C_FRAME_SIZE : integer := 1024; 

    -- TX State Machine signals
    type tx_state_t is (S_IDLE, S_REQ_RAM, S_WAIT_RAM, S_SEND_UART, S_WAIT_BUSY);
    signal tx_state     : tx_state_t := S_IDLE;
    signal tx_byte_cnt  : unsigned(15 downto 0) := (others => '0');
    
    -- Internal signals to connect to the uart_tx component
    signal tx_valid_int : std_logic := '0';
    signal tx_data_int  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy_int  : std_logic;

begin

    -- TX: send ADC data to Python
    u_tx : uart_tx
        generic map (G_CLK_HZ => G_CLK_HZ, G_BAUD => G_BAUD)
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_data  => tx_data_int,     -- Driven by state machine
            i_valid => tx_valid_int,    -- Driven by state machine
            o_busy  => tx_busy_int,     -- Read by state machine
            o_tx    => o_tx
        );

    -- RX: receive commands from Python
    u_rx : uart_rx
        generic map (G_CLK_HZ => G_CLK_HZ, G_BAUD => G_BAUD)
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_rx    => i_rx,
            o_data  => rx_data,
            o_valid => rx_valid
        );
        
    o_tx_busy <= tx_busy_int;

    -- Command decoder
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                o_duty       <= x"80";  -- default 50% duty
                o_wave_sel   <= '0';    -- default PWM mode
                o_trig_type  <= '0';
                o_trig_level <= (others => '0');
                o_dec_factor <= x"01";
                o_arm_trig   <= '0';
                o_read_req   <= '0';
                
                rx_state     <= '0';
                cmd_reg      <= (others => '0');
            else
                if rx_valid = '1' then
                    if rx_state = '0' then
                        -- STATE 0: First byte received is the Command ID
                        cmd_reg  <= rx_data;
                        rx_state <= '1';
                    else
                        -- STATE 1: Second byte received is the Data Payload
                        case cmd_reg is
                            when x"01" => 
                                o_duty <= rx_data;
                            when x"02" => 
                                o_wave_sel <= rx_data(0);
                            when x"03" => 
                                o_trig_type <= rx_data(0);
                            when x"04" => 
                                -- Lower 8 bits of Trigger Level
                                o_trig_level(7 downto 0) <= rx_data;
                            when x"05" => 
                                -- Upper 8 bits of Trigger Level
                                o_trig_level(15 downto 8) <= rx_data;
                            when x"06" => 
                                o_dec_factor <= rx_data;
                            when x"07" => 
                                -- Pulse trigger (ignores payload, just triggers on command)
                                o_arm_trig <= '1';
                            when others => 
                                -- Do nothing on invalid commands
                                null; 
                        end case;
                        
                        -- Reset state to wait for the next Command ID
                        rx_state <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                tx_state     <= S_IDLE;
                tx_byte_cnt  <= (others => '0');
                tx_valid_int <= '0';
                o_read_req   <= '0';
            else
                -- Defaults to create 1-cycle pulses unless overridden
                o_read_req   <= '0';
                tx_valid_int <= '0';

                case tx_state is
                    when S_IDLE =>
                        -- Wait for the trigger logic to say a frame is captured in RAM
                        if i_trig_good = '1' then
                            tx_byte_cnt <= (others => '0');
                            tx_state    <= S_REQ_RAM;
                        end if;

                    when S_REQ_RAM =>
                        -- Pulse read request to BRAM
                        o_read_req <= '1';
                        tx_state   <= S_WAIT_RAM;

                    when S_WAIT_RAM =>
                        -- BRAM usually takes 1 clock cycle to output data.
                        -- The data on i_tx_data is now valid.
                        tx_data_int  <= i_tx_data; 
                        tx_valid_int <= '1';       -- Tell UART to start sending
                        tx_state     <= S_SEND_UART;

                    when S_SEND_UART =>
                        -- tx_valid_int drops back to '0' here due to default assignment above.
                        -- We wait one cycle to ensure the UART module registers the 
                        -- valid signal and raises its busy flag.
                        tx_state <= S_WAIT_BUSY;

                    when S_WAIT_BUSY =>
                        -- Wait for the UART TX module to finish sending the byte
                        if tx_busy_int = '0' then
                            -- Byte sent! Check if we are done with the frame
                            if tx_byte_cnt = to_unsigned(C_FRAME_SIZE - 1, 16) then
                                tx_state <= S_IDLE; -- Frame complete, wait for next trigger
                            else
                                tx_byte_cnt <= tx_byte_cnt + 1;
                                tx_state    <= S_REQ_RAM; -- Fetch next byte
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture;