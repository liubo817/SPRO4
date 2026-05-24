-- =============================================================================
-- uart_top.vhd
-- UART interface for Python oscilloscope + wave generator
--
-- RX Packet from Python:
--   AA 55 TB_HI TB_LO VOLT TRIG CHK FF
--
-- Mapping:
--   VOLT[3:0] -> PWM duty
--   TRIG[3:0] -> Frequency select
--
-- TX Packet to Python:
--   AA 55 LEN DATA... CHK
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_top is
    generic (
        G_CLK_HZ     : integer := 100_000_000;
        G_BAUD       : integer := 115200;
        G_FRAME_SIZE : integer := 8192
        ---------------------------------------------------------------------
        -- System
        ---------------------------------------------------------------------
        );
        port (
        i_clk        : in  std_logic;
        i_rst        : in  std_logic;

        ---------------------------------------------------------------------
        -- ADC / Trigger interface
        ---------------------------------------------------------------------
        i_tx_data    : in  std_logic_vector(7 downto 0);
        i_adc_valid  : in  std_logic;
        i_trig_good  : in  std_logic;

        o_read_req   : out std_logic;
        o_trig_level : out std_logic_vector(15 downto 0);
        o_trig_type  : out std_logic;
        o_dec_factor : out std_logic_vector(7 downto 0);
        o_arm_trig   : out std_logic;

        ---------------------------------------------------------------------
        -- UART pins
        ---------------------------------------------------------------------
        i_rx         : in  std_logic;
        o_tx         : out std_logic;
        o_tx_busy    : out std_logic;
        
        o_led : out std_logic;

        ---------------------------------------------------------------------
        -- Wave generator controls
        ---------------------------------------------------------------------
        o_duty       : out std_logic_vector(3 downto 0);
        o_freq_sel   : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of uart_top is

    -------------------------------------------------------------------------
    -- UART TX component
    -------------------------------------------------------------------------
    component uart_tx is
        generic (
            G_CLK_HZ : integer;
            G_BAUD   : integer
        );
        port (
            i_clk   : in  std_logic;
            i_rst   : in  std_logic;
            i_data  : in  std_logic_vector(7 downto 0);
            i_valid : in  std_logic;
            o_busy  : out std_logic;
            o_tx    : out std_logic
        );
    end component;

    -------------------------------------------------------------------------
    -- UART RX component
    -------------------------------------------------------------------------
    component uart_rx is
        generic (
            G_CLK_HZ : integer;
            G_BAUD   : integer
        );
        port (
            i_clk   : in  std_logic;
            i_rst   : in  std_logic;
            i_rx    : in  std_logic;
            o_data  : out std_logic_vector(7 downto 0);
            o_valid : out std_logic
        );
    end component;

    -------------------------------------------------------------------------
    -- UART signals
    -------------------------------------------------------------------------
    signal rx_data      : std_logic_vector(7 downto 0);
    signal rx_valid     : std_logic;

    signal tx_data_int  : std_logic_vector(7 downto 0);
    signal tx_valid_int : std_logic;
    signal tx_busy_int  : std_logic;

    -------------------------------------------------------------------------
    -- RX FSM
    -------------------------------------------------------------------------
    type rx_state_t is (
        RX_WAIT_AA,
        RX_WAIT_55,
        RX_TB_HI,
        RX_TB_LO,
        RX_VOLT,
        RX_TRIG,
        RX_CHK,
        RX_WAIT_FF
    );

    signal rx_state : rx_state_t := RX_WAIT_AA;

    signal tb_hi_reg : std_logic_vector(7 downto 0);
    signal tb_lo_reg : std_logic_vector(7 downto 0);
    signal volt_reg  : std_logic_vector(7 downto 0);
    signal trig_reg  : std_logic_vector(7 downto 0);
    signal chk_reg   : std_logic_vector(7 downto 0);

    -------------------------------------------------------------------------
    -- TX FSM
    -------------------------------------------------------------------------
    type tx_state_t is (
        TX_IDLE,
        TX_SEND_AA,
        TX_SEND_55,
        TX_SEND_LEN,
        --TX_REQ_DATA,
        TX_SEND_DATA,
        TX_WAIT_BUSY_START,
        TX_WAIT_BUSY,
        TX_SEND_CHK
    );

    signal tx_state : tx_state_t := TX_IDLE;

    signal tx_index : unsigned(15 downto 0) := (others => '0');

    signal checksum : unsigned(7 downto 0) := (others => '0');

    signal tx_ret_state : tx_state_t := TX_IDLE;

begin

    -------------------------------------------------------------------------
    -- UART transmitter
    -------------------------------------------------------------------------
    u_tx : uart_tx
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_BAUD   => G_BAUD
        )
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_data  => tx_data_int,
            i_valid => tx_valid_int,
            o_busy  => tx_busy_int,
            o_tx    => o_tx
        );

    -------------------------------------------------------------------------
    -- UART receiver
    -------------------------------------------------------------------------
    u_rx : uart_rx
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_BAUD   => G_BAUD
        )
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_rx    => i_rx,
            o_data  => rx_data,
            o_valid => rx_valid
        );

    o_tx_busy <= tx_busy_int;
    o_trig_level <= x"00" & trig_reg;
    o_trig_type <= '0';
    o_dec_factor <= tb_hi_reg;

    -------------------------------------------------------------------------
    -- RX Packet Parser
    -------------------------------------------------------------------------
    process(i_clk)

        variable chk_calc : unsigned(7 downto 0);

    begin
        if rising_edge(i_clk) then

            if i_rst = '1' then

                rx_state <= RX_WAIT_AA;
                
                trig_reg <= x"7F";
                o_trig_type <= '0';
                tb_hi_reg <= x"01";

                

                o_duty     <= "1000"; -- 50%
                o_freq_sel <= "0001"; -- 100 Hz

            else
                o_arm_trig <= '0';

                if rx_valid = '1' then

                    case rx_state is

                        -----------------------------------------------------
                        when RX_WAIT_AA =>

                            if rx_data = x"AA" then
                                rx_state <= RX_WAIT_55;
                            end if;

                        -----------------------------------------------------
                        when RX_WAIT_55 =>

                            if rx_data = x"55" then
                                rx_state <= RX_TB_HI;
                            else
                                rx_state <= RX_WAIT_AA;
                            end if;

                        -----------------------------------------------------
                        when RX_TB_HI =>

                            tb_hi_reg <= rx_data;
                            rx_state  <= RX_TB_LO;

                        -----------------------------------------------------
                        when RX_TB_LO =>

                            tb_lo_reg <= rx_data;
                            rx_state  <= RX_VOLT;

                        -----------------------------------------------------
                        when RX_VOLT =>

                            volt_reg <= rx_data;
                            rx_state <= RX_TRIG;

                        -----------------------------------------------------
                        when RX_TRIG =>

                            trig_reg <= rx_data;
                            rx_state <= RX_CHK;

                        -----------------------------------------------------
                        when RX_CHK =>

                            chk_reg  <= rx_data;
                            rx_state <= RX_WAIT_FF;

                        -----------------------------------------------------
                        when RX_WAIT_FF =>
                            o_arm_trig <= '1';

                            if rx_data = x"FF" then

                                chk_calc :=
                                    unsigned(tb_hi_reg) +
                                    unsigned(tb_lo_reg) +
                                    unsigned(volt_reg)  +
                                    unsigned(trig_reg);

                                if std_logic_vector(chk_calc) = chk_reg then

                                    -------------------------------------------------
                                    -- Map Python packet fields to wave generator
                                    -------------------------------------------------
                                    o_duty     <= volt_reg(3 downto 0);
                                    o_freq_sel <= trig_reg(3 downto 0);

                                end if;
                            end if;

                            rx_state <= RX_WAIT_AA;

                    end case;
                end if;
            end if;
        end if;
        
    
    end process;

    -------------------------------------------------------------------------
    -- TX Packet Generator
    -------------------------------------------------------------------------
    process(i_clk)
    begin
        if rising_edge(i_clk) then

            if i_rst = '1' then

                tx_state      <= TX_IDLE;
                tx_valid_int  <= '0';
                tx_data_int   <= (others => '0');

                tx_index      <= (others => '0');
                checksum      <= (others => '0');

                o_read_req    <= '0';

            else

                tx_valid_int <= '0';
                o_read_req   <= '0';

                case tx_state is

                    ---------------------------------------------------------
                    when TX_IDLE =>

                        if i_trig_good = '1' then

                            tx_index <= (others => '0');
                            checksum <= (others => '0');

                            tx_state <= TX_SEND_AA;

                        end if;

                    ---------------------------------------------------------
                    when TX_SEND_AA =>

                        if tx_busy_int = '0' then

                            tx_data_int  <= x"AA";
                            tx_valid_int <= '1';

                            tx_ret_state <= TX_SEND_55;
                            tx_state     <= TX_WAIT_BUSY_START;

                        end if;
                        o_led <='1';

                    ---------------------------------------------------------
                    when TX_SEND_55 =>

                        if tx_busy_int = '0' then

                            tx_data_int  <= x"55";
                            tx_valid_int <= '1';

                            tx_ret_state <= TX_SEND_DATA;
                            tx_state     <= TX_WAIT_BUSY_START;

                        end if;

                    ---------------------------------------------------------
                    when TX_SEND_LEN =>

                        if tx_busy_int = '0' then

                            tx_data_int <= x"00";

                            tx_valid_int <= '1';

                            --tx_state <= TX_REQ_DATA;
                            --tx_state <= TX_SEND_DATA;
                            tx_ret_state <= TX_SEND_DATA;
                            tx_state     <= TX_WAIT_BUSY_START;

                        end if;

                    ---------------------------------------------------------
                    --when TX_REQ_DATA =>

                        --o_read_req <= '1';

                        --tx_state <= TX_SEND_DATA;

                    ---------------------------------------------------------
                    when TX_SEND_DATA =>

                        if tx_busy_int = '0' then
                            o_read_req <= '1';

                            tx_data_int  <= i_tx_data;
                            tx_valid_int <= '1';

                            checksum <= checksum + unsigned(i_tx_data);

                            tx_ret_state <= TX_WAIT_BUSY;

                            tx_state <= TX_WAIT_BUSY_START;

                        end if;
                        
                    when TX_WAIT_BUSY_START =>
                        -- Give the sub-module a cycle to drop into busy mode
                        if tx_busy_int = '1' then 
                            tx_state <= tx_ret_state;
                        end if;

                    ---------------------------------------------------------
                    when TX_WAIT_BUSY =>

                        if tx_busy_int = '0' then

                            if tx_index = to_unsigned(G_FRAME_SIZE - 1, 16) then

                                tx_state <= TX_IDLE;

                            else

                                tx_index <= tx_index + 1;

                                tx_state <= TX_SEND_DATA;

                            end if;
                        end if;

                    ---------------------------------------------------------
                    when TX_SEND_CHK =>

                        if tx_busy_int = '0' then

                            tx_data_int  <= std_logic_vector(checksum);
                            tx_valid_int <= '1';

                            tx_state <= TX_IDLE;

                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture;