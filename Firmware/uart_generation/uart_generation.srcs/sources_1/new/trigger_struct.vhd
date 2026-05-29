----------------------------------------------------------------------------------
-- trigger_struct.vhd
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

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
    i_dec_factor  : in std_logic_vector(7 downto 0);
    
    o_led2 : out std_logic;
    o_led3 : out std_logic;
    o_led4 : out std_logic;
    o_led5 : out std_logic

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
    signal prev_sample   : unsigned(15 downto 0) := (others => '0');

    constant PRE_TRIG_DEPTH  : unsigned(11 downto 0) := to_unsigned(2048, 12);
    constant POST_TRIG_DEPTH : unsigned(11 downto 0) := to_unsigned(2047, 12);
    
    signal auto_trig_cnt : unsigned(15 downto 0) := (others => '0');

    constant AUTO_TIMEOUT_VAL : unsigned(15 downto 0) := x"FFFF";

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
                
                data_valid <= '0';

                case current_state is
                    
                    when IDLE =>
                        wr_ptr     <= (others => '0');
                        fill_count <= (others => '0');
                        byte_sel   <= '0';
                        auto_trig_cnt <= (others => '0');
                        --if arm_trigger = '1' then
                            current_state <= PRE_FILL;
                        --end if;
                        o_led3 <= '1';
                        o_led4 <= '0';
                        o_led5 <= '0';

                    when PRE_FILL =>
                        -- Only capture and step forward when downsampled data arrives
                        o_led4 <= '1';
                        o_led3 <= '0';
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
                            circular_bram(to_integer(wr_ptr)) <= o_dec_output; -- write data into bram
                            wr_ptr <= wr_ptr + 1; -- increment bram pointer
                            
                            auto_trig_cnt <= auto_trig_cnt + 1;
                            o_led5 <= '1';

                            if arm_trigger = '1' then
                                trig_ptr      <= wr_ptr;        
                                fill_count    <= (others => '0');
                                auto_trig_cnt <= (others => '0');
                                current_state <= POST_FILL;     
                            end if;
                            
                                -- Trigger Check
                                if ((i_trig_type = '1' and prev_sample < unsigned(i_trig_level) and unsigned(o_dec_output) >= unsigned(i_trig_level)) or (i_trig_type = '0' and prev_sample > unsigned(i_trig_level) and unsigned(o_dec_output) <= unsigned(i_trig_level))) then
                                    trig_ptr      <= wr_ptr; -- Latch the trigger location
                                    fill_count    <= (others => '0');
                                    auto_trig_cnt <= (others => '0'); -- Clear watchdog
                                    current_state <= POST_FILL;
                                
                                elsif auto_trig_cnt >= AUTO_TIMEOUT_VAL then
                                    trig_ptr      <= wr_ptr;          -- Capture wherever the pointer is right now
                                    fill_count    <= (others => '0');
                                    auto_trig_cnt <= (others => '0'); -- Clear watchdog
                                    current_state <= POST_FILL;       
                                end if;
                            
                        end if;

                    when POST_FILL =>
                        if dec_data_v = '1' then
                            circular_bram(to_integer(wr_ptr)) <= o_dec_output;
                            wr_ptr     <= wr_ptr + 1;
                            fill_count <= fill_count + 1;

                            if fill_count >= POST_TRIG_DEPTH then

                                rd_ptr        <= trig_ptr - PRE_TRIG_DEPTH; 
                                fill_count    <= (others => '0');
                                byte_sel      <= '0';
                                current_state <= TX_READY;
                            end if;
                        end if;

                    when TX_READY =>
                        -- Wake up uart
                        data_valid <= '1';
                        
                        -- Process incoming read requests from UART
                        if i_read_req = '1' then
                            if byte_sel = '0' then
                                -- High byte read complete
                                byte_sel <= '1';
                            else
                                -- Low byte read complete
                                byte_sel <= '0';
                                rd_ptr   <= rd_ptr + 1;
                                fill_count <= fill_count + 1;
                                
                                if fill_count = 4095 then
                                    current_state <= IDLE;
                                end if;
                            end if;
                        end if;

                end case;

                if dec_data_v = '1' then
                    prev_sample <= unsigned(o_dec_output);
                end if;

            end if;
        end if;
    end process;
    
    process(t_clk)
    begin
        if rising_edge(t_clk) then
            bram_read_data <= circular_bram(to_integer(rd_ptr));
        end if;
    end process;
    
    o_led2 <= i_adc_data(0); -- Bit 0
    -- o_led3 <= i_adc_data(1); -- Bit 1
    -- o_led4 <= i_adc_data(2); -- Bit 2
    -- o_led5 <= i_adc_data(3); -- Bit 3
    
    o_buffer <= bram_read_data(15 downto 8) when byte_sel = '0' else 
                bram_read_data(7 downto 0);
                
    o_trig_good <= data_valid;

end Structural;
