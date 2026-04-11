-- =============================================================================
-- uart_tx.vhd  --  Simple UART Transmitter, 8N1
-- 100 MHz clock, 115200 baud by default
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        G_CLK_HZ : integer := 100_000_000;
        G_BAUD   : integer := 115_200
    );
    port (
        i_clk   : in  std_logic;
        i_rst   : in  std_logic;                     -- active-high sync reset
        i_data  : in  std_logic_vector(7 downto 0);  -- byte to send
        i_valid : in  std_logic;                     -- pulse high 1 clk to send
        o_busy  : out std_logic;                     -- high while transmitting
        o_tx    : out std_logic                      -- serial output to FTDI
    );
end entity;

architecture rtl of uart_tx is

    constant C_TICKS : integer := G_CLK_HZ / G_BAUD;

    type t_state is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state    : t_state := IDLE;
    signal tick_cnt : integer range 0 to C_TICKS - 1 := 0;
    signal bit_idx  : integer range 0 to 7 := 0;
    signal shreg    : std_logic_vector(7 downto 0);
    signal tx_r     : std_logic := '1';

begin
    o_tx   <= tx_r;
    o_busy <= '0' when state = IDLE else '1';

    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                state    <= IDLE;
                tick_cnt <= 0;
                bit_idx  <= 0;
                tx_r     <= '1';
            else
                case state is

                    when IDLE =>
                        tx_r <= '1';
                        if i_valid = '1' then
                            shreg    <= i_data;
                            tick_cnt <= 0;
                            state    <= START_BIT;
                        end if;

                    when START_BIT =>
                        tx_r <= '0';
                        if tick_cnt = C_TICKS - 1 then
                            tick_cnt <= 0;
                            bit_idx  <= 0;
                            state    <= DATA_BITS;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when DATA_BITS =>
                        tx_r <= shreg(bit_idx);
                        if tick_cnt = C_TICKS - 1 then
                            tick_cnt <= 0;
                            if bit_idx = 7 then
                                state <= STOP_BIT;
                            else
                                bit_idx <= bit_idx + 1;
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when STOP_BIT =>
                        tx_r <= '1';
                        if tick_cnt = C_TICKS - 1 then
                            tick_cnt <= 0;
                            state    <= IDLE;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture;