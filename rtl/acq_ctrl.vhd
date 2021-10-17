library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
entity acq_ctrl is
  generic (
    SAMPLE_COUNT  : integer := 53000;
    FRQ_BIN_COUNT : integer := 54
  );
  port (
    reset_n                    : in std_logic;
    clk                        : in std_logic;
    fifo_in_valid              : in std_logic;
    carrier_complex_mult_valid : in std_logic;
    inv_fft_valid              : in std_logic;
    prn_idx                    : in std_logic_vector(4 downto 0);
    inv_fft_data               : in std_logic_vector(79 downto 0);
    prn_fft_data               : in std_logic_vector(79 downto 0);

    prn_fft_conj           : out std_logic_vector(79 downto 0);
    abs_inv_fft_data       : out std_logic_vector(80 downto 0);
    data_bram_addr         : out std_logic_vector(31 downto 0);
    data_bram_we           : out std_logic;
    acq_decode_valid       : out std_logic;
    dds_phase_config_data  : out std_logic_vector(23 downto 0);
    dds_phase_config_valid : out std_logic;
    fifo_in_re             : out std_logic;
    PRN_bram_addr          : out std_logic_vector(31 downto 0);
    PRN_valid              : out std_logic;
    axi_dma_tlast          : out std_logic

  );
end acq_ctrl;
architecture Behavioral of acq_ctrl is
  type State_Type is (INIT,
    READ_DATA_TO_BRAM,
    WAIT_FOR_INV_FFT_VALID,
    TLAST_GEN
  );

  signal state_next, state_reg                         : State_Type;
  signal sample_cnt_next, sample_cnt_reg               : unsigned(31 downto 0);
  signal PRN_cnt_next, PRN_cnt_reg                     : unsigned(31 downto 0);
  signal acq_decoder_valid_next, acq_decoder_valid_reg : std_logic;
  signal frq_bin_cnt_next, frq_bin_cnt_reg             : unsigned(31 downto 0);
  signal PRN_valid_next, PRN_valid_reg                 : std_logic;

  function conj_func(X : std_logic_vector(79 downto 0))
    return std_logic_vector is
    variable TMP : signed(39 downto 0) := (others => '0');
  begin
    TMP := - signed(X(79 downto 40));
    return std_logic_vector(TMP) & X(39 downto 0);
  end conj_func;

  function abs_func(X : std_logic_vector(79 downto 0))
    return std_logic_vector is
    variable TMP : signed(39 downto 0) := (others => '0');
  begin
    TMP := signed(X(79 downto 40)) * signed(X(79 downto 40)) + signed(X(39 downto 0)) * signed(X(39 downto 0));
    return std_logic_vector(TMP);
  end abs_func;

begin

  -- combinatorial circuits
  PRN_bram_addr         <= std_logic_vector(PRN_cnt_reg);
  prn_fft_conj          <= conj_func(prn_fft_data);
  abs_inv_fft_data      <= abs_func(inv_fft_data);
  dds_phase_config_data <= std_logic_vector(frq_bin_cnt_reg);
  acq_decode_valid      <= acq_decoder_valid_reg;
  PRN_valid             <= PRN_valid_reg;
  ------------------- The state machine -----------------------

  -- sequential part
  process (clk)
  begin
    if (rising_edge(clk)) then
      -- synchronous reset
      if (reset_n = '0') then
        state_reg             <= INIT;
        sample_cnt_reg        <= (others => '0');
        PRN_cnt_reg           <= (others => '0');
        acq_decoder_valid_reg <= '0';
        frq_bin_cnt_reg       <= (others => '0');
        PRN_valid_reg         <= '0';
      else
        state_reg             <= state_next;
        sample_cnt_reg        <= sample_cnt_next;
        PRN_cnt_reg           <= PRN_cnt_next;
        acq_decoder_valid_reg <= acq_decoder_valid_next;
        frq_bin_cnt_reg       <= frq_bin_cnt_next;
        PRN_valid_reg         <= PRN_valid_next;
      end if;
    end if;
  end process;

  -- combinatorial part
  process (all)
  begin
    --default assignments
    state_next             <= state_reg;
    sample_cnt_next        <= sample_cnt_next;
    PRN_cnt_next           <= PRN_cnt_reg;
    fifo_in_re             <= '0';
    acq_decoder_valid_next <= '0';
    axi_dma_tlast          <= '0';
    dds_phase_config_valid <= '0';
    frq_bin_cnt_next       <= frq_bin_cnt_reg;
    PRN_valid_next         <= PRN_valid_reg;
    data_bram_we           <= '0';
    case state_reg is
      when INIT =>
        if (fifo_in_valid = '1') then
          state_next   <= READ_DATA_TO_BRAM;
          PRN_cnt_next <= 1023 * unsigned(prn_idx);
        end if;

      when READ_DATA_TO_BRAM =>
        if (sample_cnt_reg < SAMPLE_COUNT) then
          if (fifo_in_valid = '1') then
            sample_cnt_next <= sample_cnt_reg + 1;
            fifo_in_re      <= '1';
            data_bram_addr  <= std_logic_vector(sample_cnt_reg);
            data_bram_we    <= '1';
          end if;
        else
          state_next      <= WAIT_FOR_INV_FFT_VALID;
          sample_cnt_next <= (others => '0');
        end if;

        -- This state includes the configuration of DDS phase and the needed configurations for 
        -- PRN FFT, CARRIER FFT. Finally, it waits for the inv_fft_valid
        -- PRN FFT and CARRIER FFT should start at the same time.
        -- To do that carrier_complex_mult_valid and corresponding data must be delayed one clock cycle.
      when WAIT_FOR_INV_FFT_VALID =>
        if (inv_fft_valid = '0') then
          if (sample_cnt_reg < SAMPLE_COUNT) then
            if (carrier_complex_mult_valid = '0') then
              sample_cnt_next        <= sample_cnt_reg + 1;
              data_bram_addr         <= std_logic_vector(sample_cnt_reg);
              acq_decoder_valid_next <= '1';
            else
              if (PRN_cnt_reg < 1023) then
                PRN_cnt_next <= PRN_cnt_reg + 1;
              end if;
              sample_cnt_next <= sample_cnt_reg + 1;
              PRN_valid_next  <= '1';
            end if;
          else
            PRN_valid_next <= '0';
          end if;
        else
          state_next      <= TLAST_GEN;
          sample_cnt_next <= (others => '0');
        end if;

      when TLAST_GEN =>
        if (sample_cnt_reg < SAMPLE_COUNT) then
          sample_cnt_next <= sample_cnt_reg + 1;
        else
          if frq_bin_cnt_reg < FRQ_BIN_COUNT then
            frq_bin_cnt_next       <= frq_bin_cnt_reg + 1;
            dds_phase_config_valid <= '1';
            state_next             <= WAIT_FOR_INV_FFT_VALID;
          else
            state_next <= INIT;
          end if;
          axi_dma_tlast <= '1';
        end if;

    end case;
  end process;

end Behavioral;