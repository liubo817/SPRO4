----------------------------------------------------------------------------------
-- shit
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;


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
    signal dec_data_v   : std_logic := '0';
    
    type ram_type is array (0 to 4095) of std_logic_vector(15 downto 0);
    signal circular_bram : ram_type := (others => (others => '0'));
    
    signal wr_ptr : unsigned(11 downto 0) := (others => '0');
    signal rd_ptr : unsigned(11 downto 0) := (others => '0');
    
    signal bram_read_data : std_logic_vector(15 downto 0);
    
    type state_type is (IDLE, PRE_FILL, ARMED, POST_FILL, TX_READY);
    signal current_state : state_type := IDLE;

    -- Counters and Pointers
    signal fill_count    : unsigned(11 downto 0) := (others => '0');
    signal trig_ptr      : unsigned(11 downto 0) := (others => '0');
    signal prev_sample   : signed(15 downto 0) := (others => '0');

    -- Configuration Constants (For a 4096 depth BRAM)
    constant PRE_TRIG_DEPTH  : unsigned(11 downto 0) := to_unsigned(2048, 12);
    constant POST_TRIG_DEPTH : unsigned(11 downto 0) := to_unsigned(2047, 12);

    component decimator is
        port (
            d_clk : in std_logic;
            d_reset : in std_logic;

            i_adc_valid : in std_logic;
            i_adc_in : in std_logic_vector(15 downto 0);

            i_dec_factor : in std_logic_vector(7 downto 0);
            o_dec_valid : out std_logic;
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
        o_dec_valid => dec_data_v,
        o_dec_output => o_dec_output
    );
    
    -- -------------------------------------------------------------------------
    -- MAIN CONTROL FSM & BRAM WRITE PORT (Port A)
    -- -------------------------------------------------------------------------
    process(t_clk)
    begin
        if rising_edge(t_clk) then
            if t_reset = '1' then
                current_state <= IDLE;
                wr_ptr        <= (others => '0');
                fill_count    <= (others => '0');
                data_valid    <= '0';
                byte_sel      <= '0';
                prev_sample   <= (others => '0');
            else
                -- Default assignment: clear valid unless in the transmission state
                data_valid <= '0';

                case current_state is
                    
                    when IDLE =>
                        wr_ptr     <= (others => '0');
                        fill_count <= (others => '0');
                        byte_sel   <= '0';
                        if arm_trigger = '1' then
                            current_state <= PRE_FILL;
                        end if;

                    when PRE_FILL =>
                        -- Only capture and step forward when downsampled data arrives
                        if dec_data_v = '1' then
                            circular_bram(to_integer(wr_ptr)) <= o_dec_output;
                            wr_ptr     <= wr_ptr + 1;
                            fill_count <= fill_count + 1;
                            
                            if fill_count >= (PRE_TRIG_DEPTH - 1) then
                                current_state <= ARMED;
                            end if;
                        end if;

                    when ARMED =>
                        if dec_data_v = '1' then
                            circular_bram(to_integer(wr_ptr)) <= o_dec_output;
                            wr_ptr <= wr_ptr + 1;
                            
                            -- Rising Edge Trigger Check
                            if i_trig_type = '1' then
                                if (prev_sample < signed(i_trig_level)) and (signed(o_dec_output) >= signed(i_trig_level)) then
                                    trig_ptr      <= wr_ptr; -- Latch the trigger location
                                    fill_count    <= (others => '0');
                                    current_state <= POST_FILL;
                                end if;
                            -- Falling Edge Trigger Check
                            else
                                if (prev_sample > signed(i_trig_level)) and (signed(o_dec_output) <= signed(i_trig_level)) then
                                    trig_ptr      <= wr_ptr;
                                    fill_count    <= (others => '0');
                                    current_state <= POST_FILL;
                                end if;
                            end if;
                        end if;

                    when POST_FILL =>
                        if dec_data_v = '1' then
                            circular_bram(to_integer(wr_ptr)) <= o_dec_output;
                            wr_ptr     <= wr_ptr + 1;
                            fill_count <= fill_count + 1;

                            if fill_count >= POST_TRIG_DEPTH then
                                -- Memory is perfectly balanced. Stop writing!
                                -- Calculate the oldest sample location to start readout sequence cleanly
                                rd_ptr        <= trig_ptr - PRE_TRIG_DEPTH; 
                                fill_count    <= (others => '0');
                                byte_sel      <= '0';
                                current_state <= TX_READY;
                            end if;
                        end if;

                    when TX_READY =>
                        -- Wake up the UART controller
                        data_valid <= '1';
                        
                        -- Process incoming read requests from UART
                        if i_read_req = '1' then
                            if byte_sel = '0' then
                                -- High byte read complete. Expose the low byte next.
                                byte_sel <= '1';
                            else
                                -- Low byte read complete. Advance memory address.
                                byte_sel <= '0';
                                rd_ptr   <= rd_ptr + 1;
                                fill_count <= fill_count + 1;
                                
                                -- Check if all 4096 words (8192 bytes) have been extracted
                                if fill_count = 4095 then
                                    current_state <= IDLE;
                                end if;
                            end if;
                        end if;

                end case;

                -- Track histories only on valid data iterations
                if dec_data_v = '1' then
                    prev_sample <= signed(o_dec_output);
                end if;

            end if;
        end if;
    end process;
    
    -- -------------------------------------------------------------------------
    -- PORT B: Read Port (Synchronous BRAM Inferences)
    -- -------------------------------------------------------------------------
    process(t_clk)
    begin
        if rising_edge(t_clk) then
            bram_read_data <= circular_bram(to_integer(rd_ptr));
        end if;
    end process;
    
    -- Multiplex high and low bytes of the extracted memory data out to your UART
    o_buffer <= bram_read_data(15 downto 8) when byte_sel = '0' else 
                bram_read_data(7 downto 0);
                
    o_trig_good <= data_valid;

end Structural;
