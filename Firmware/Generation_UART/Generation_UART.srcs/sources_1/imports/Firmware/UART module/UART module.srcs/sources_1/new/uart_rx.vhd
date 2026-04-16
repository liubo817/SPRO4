-- =============================================================================
-- uart_rx.vhd  --  Simple UART Receiver, 8N1
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        G_CLK_HZ : integer := 100_000_000;
        G_BAUD   : integer := 115_200
    );
    port (
        i_clk   : in  std_logic;
        i_rst   : in  std_logic;
        i_rx    : in  std_logic;                     -- serial input from FTDI
        o_data  : out std_logic_vector(7 downto 0);  -- received byte
        o_valid : out std_logic                      -- pulses 1 clk when byte ready
    );
end entity;

architecture Behavioral of uart_rx is
    constant C_TICKS      : integer := G_CLK_HZ / G_BAUD;
    constant C_HALF_TICKS : integer := C_TICKS / 2;

    type t_state is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state    : t_state := IDLE;
    signal tick_cnt : integer range 0 to C_TICKS - 1 := 0;
    signal bit_idx  : integer range 0 to 7 := 0;
    signal shreg    : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_sync  : std_logic_vector(1 downto 0) := "11";  -- 2FF synchroniser
begin

    -- Double flip-flop synchroniser (prevents metastability on async RX line)
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            rx_sync <= rx_sync(0) & i_rx;
        end if;
    end process;

    process(i_clk)
    begin
        if rising_edge(i_clk) then
            o_valid <= '0';  -- default

            if i_rst = '1' then
                state    <= IDLE;
                tick_cnt <= 0;
                bit_idx  <= 0;
            else
                case state is

                    when IDLE =>
                        if rx_sync(1) = '0' then  -- falling edge = start bit
                            tick_cnt <= 0;
                            state    <= START_BIT;
                        end if;

                    -- Wait half a bit period to sample in the middle of start bit
                    when START_BIT =>
                        if tick_cnt = C_HALF_TICKS - 1 then
                            tick_cnt <= 0;
                            bit_idx  <= 0;
                            state    <= DATA_BITS;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    -- Sample each bit in the middle of its period
                    when DATA_BITS =>
                        if tick_cnt = C_TICKS - 1 then
                            tick_cnt        <= 0;
                            shreg(bit_idx)  <= rx_sync(1);
                            if bit_idx = 7 then
                                state <= STOP_BIT;
                            else
                                bit_idx <= bit_idx + 1;
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when STOP_BIT =>
                        if tick_cnt = C_TICKS - 1 then
                            tick_cnt <= 0;
                            o_data   <= shreg;
                            o_valid  <= '1';  -- byte is ready
                            state    <= IDLE;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture;