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
    complex_mult_in            : in std_logic_vector(79 downto 0);
    inv_fft_valid              : in std_logic;
    prn_idx                    : in std_logic_vector(4 downto 0);
    inv_fft_data               : in std_logic_vector(79 downto 0);
    prn_fft_data               : in std_logic_vector(79 downto 0);
    dma_ready             : in std_logic;
    complex_delayed_valid      : out std_logic;
    complex_delayed_data       : out std_logic_vector(79 downto 0);
    prn_fft_conj               : out std_logic_vector(79 downto 0);
    abs_inv_fft_data           : out std_logic_vector(79 downto 0);
    data_bram_addr             : out std_logic_vector(31 downto 0);
    data_bram_we               : out std_logic;
    acq_decode_valid           : out std_logic;
    dds_phase_config_data      : out std_logic_vector(23 downto 0);
    dds_phase_config_valid     : out std_logic;
    fifo_in_re                 : out std_logic;
    PRN_bram_addr              : out std_logic_vector(31 downto 0);
    PRN_valid                  : out std_logic;
    axi_dma_tlast              : out std_logic;
    inv_fft_config_valid       : out std_logic;
    inv_fft_config_data        : out std_logic_vector(7 downto 0);
    abs_valid                  : out std_logic

  );
end acq_ctrl;
architecture Behavioral of acq_ctrl is
  type State_Type is (INIT,
    READ_DATA_TO_BRAM,
    WAIT_FOR_INV_FFT_VALID,
    TLAST_GEN
  );

  signal state_next, state_reg                                                          : State_Type;
  signal sample_cnt_next, sample_cnt_reg                                                : unsigned(31 downto 0);
  signal PRN_cnt_next, PRN_cnt_reg                                                      : unsigned(31 downto 0);
  signal valid_cnt_next, valid_cnt_reg                                                  : unsigned(31 downto 0);
  signal abs_cnt_next, abs_cnt_reg                                                      : unsigned(31 downto 0);
  signal eight_cnt_next, eight_cnt_reg                                                  : unsigned(31 downto 0);
  signal abs_valid_reg0, abs_valid_reg1, abs_valid_reg2, abs_valid_reg3                 : std_logic;
  signal acq_decoder_valid_next, acq_decoder_valid_reg                                  : std_logic;
  signal ctrl_tlast                                                                     : std_logic;
  signal axi_dma_tlast_reg0, axi_dma_tlast_reg1, axi_dma_tlast_reg2, axi_dma_tlast_reg3 : std_logic;
  signal bram_we                                                                        : std_logic;

  signal frq_bin_cnt_next, frq_bin_cnt_reg : unsigned(31 downto 0);
  signal PRN_valid_next, PRN_valid_reg     : std_logic;

  function conj_func(X : std_logic_vector(79 downto 0))
    return std_logic_vector is
    variable TMP : signed(39 downto 0) := (others => '0');
  begin
    TMP := - signed(X(79 downto 40));
    return std_logic_vector(TMP) & X(39 downto 0);
  end conj_func;

  function abs_func(X : std_logic_vector(79 downto 0))
    return std_logic_vector is
    variable TMP : signed(79 downto 0) := (others => '0');
  begin
    TMP := signed(X(79 downto 40)) * signed(X(79 downto 40)) + signed(X(39 downto 0)) * signed(X(39 downto 0));
    return std_logic_vector(TMP);
  end abs_func;

begin

  -- combinatorial circuits
  PRN_bram_addr         <= std_logic_vector(PRN_cnt_reg);
  prn_fft_conj          <= conj_func(prn_fft_data);
  abs_inv_fft_data      <= abs_func(inv_fft_data);
  dds_phase_config_data <= std_logic_vector(frq_bin_cnt_reg(23 downto 0));
  acq_decode_valid      <= acq_decoder_valid_reg;
  PRN_valid             <= PRN_valid_reg;
  data_bram_addr        <= std_logic_vector(sample_cnt_reg) when bram_we = '1' else std_logic_vector(eight_cnt_reg);
  data_bram_we          <= bram_we;
  abs_valid             <= abs_valid_reg3;
  axi_dma_tlast         <= axi_dma_tlast_reg1;
  ------------------- The state machine -----------------------

  -- sequential part
  process (clk)
  begin
    if (rising_edge(clk)) then
      -- synchronous reset
      if (reset_n = '0') then
        state_reg             <= INIT;
        sample_cnt_reg        <= (others => '0');
        eight_cnt_reg         <= to_unsigned(7, 32);
        PRN_cnt_reg           <= (others => '0');
        acq_decoder_valid_reg <= '0';
        frq_bin_cnt_reg       <= (others => '0');
        PRN_valid_reg         <= '0';
        valid_cnt_next        <= (others => '0');
      else
        state_reg             <= state_next;
        sample_cnt_reg        <= sample_cnt_next;
        eight_cnt_reg         <= eight_cnt_next;
        PRN_cnt_reg           <= PRN_cnt_next;
        acq_decoder_valid_reg <= acq_decoder_valid_next;
        frq_bin_cnt_reg       <= frq_bin_cnt_next;
        PRN_valid_reg         <= PRN_valid_next;
        valid_cnt_next        <= valid_cnt_reg;
      end if;
    end if;
  end process;

  -- combinatorial part
  process (state_reg, fifo_in_valid, sample_cnt_reg, inv_fft_valid, carrier_complex_mult_valid,
    PRN_cnt_reg, frq_bin_cnt_reg, PRN_valid_reg, prn_idx, valid_cnt_reg, eight_cnt_reg)
  begin
    --default assignments
    state_next             <= state_reg;
    sample_cnt_next        <= sample_cnt_reg;
    PRN_cnt_next           <= PRN_cnt_reg;
    fifo_in_re             <= '0';
    acq_decoder_valid_next <= acq_decoder_valid_reg;
    valid_cnt_next         <= valid_cnt_reg;
    eight_cnt_next         <= eight_cnt_reg;
    ctrl_tlast             <= '0';
    dds_phase_config_valid <= '0';
    frq_bin_cnt_next       <= frq_bin_cnt_reg;
    PRN_valid_next         <= PRN_valid_reg;
    bram_we                <= '0';
    inv_fft_config_valid   <= '0';
    inv_fft_config_data    <= (others => '0');
    case state_reg is
      when INIT =>
        if (fifo_in_valid = '1') then
          state_next               <= READ_DATA_TO_BRAM;
          PRN_cnt_next(9 downto 0) <= 1023 * unsigned(prn_idx);
          inv_fft_config_data      <= "00000000";
          inv_fft_config_valid     <= '1';
        end if;

      when READ_DATA_TO_BRAM =>
        if (sample_cnt_reg < SAMPLE_COUNT) then
          if (fifo_in_valid = '1') then
            sample_cnt_next <= sample_cnt_reg + 1;
            fifo_in_re      <= '1';
            bram_we         <= '1';
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
          if (valid_cnt_reg < SAMPLE_COUNT) then
            if (eight_cnt_reg(2 downto 0) = "000") then
              eight_cnt_next <= eight_cnt_reg + 15;
            else
              eight_cnt_next <= eight_cnt_reg - 1;
            end if;
            sample_cnt_next <= sample_cnt_reg + 1;
            if (carrier_complex_mult_valid = '0') then
              acq_decoder_valid_next <= '1';
            else
              valid_cnt_next <= valid_cnt_reg + 1;
              if (PRN_cnt_reg < 1023) then
                PRN_cnt_next <= PRN_cnt_reg + 1;
              end if;
              PRN_valid_next <= '1';
            end if;
          else
            PRN_valid_next         <= '0';
            acq_decoder_valid_next <= '0';
          end if;
        else
          state_next      <= TLAST_GEN;
          sample_cnt_next <= (others => '0');
          eight_cnt_next  <= to_unsigned(7, 32);
          valid_cnt_next  <= (others => '0');
        end if;

      when TLAST_GEN =>
        if dma_ready = '1' then
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
            ctrl_tlast <= '1';
          end if;
        end if;
    end case;
  end process;

  -- Process for generating complex multiplier delayed data and valid signals
  process (clk)
  begin
    if rising_edge(clk) then
      if (carrier_complex_mult_valid = '1') then
        complex_delayed_valid <= '1';
        complex_delayed_data  <= complex_mult_in;
      else
        complex_delayed_data  <= (others => '0');
        complex_delayed_valid <= '0';
      end if;
    end if;
  end process;
  -- Process for abs_valid and tlast
  process (clk)
  begin
    if (rising_edge(clk)) then
      -- synchronous reset
      if (reset_n = '0') then
        abs_valid_reg0 <= '0';
        abs_valid_reg1 <= '0';
        abs_valid_reg2 <= '0';
        abs_valid_reg3 <= '0';

        axi_dma_tlast_reg0 <= '0';
        axi_dma_tlast_reg0 <= '0';
        axi_dma_tlast_reg0 <= '0';
        axi_dma_tlast_reg0 <= '0';
      else
        abs_valid_reg0 <= dma_ready and inv_fft_valid;
        abs_valid_reg1 <= abs_valid_reg0;
        abs_valid_reg2 <= abs_valid_reg1;
        abs_valid_reg3 <= abs_valid_reg2;

        axi_dma_tlast_reg0 <= ctrl_tlast;
        axi_dma_tlast_reg1 <= axi_dma_tlast_reg0;
        axi_dma_tlast_reg2 <= axi_dma_tlast_reg1;
        axi_dma_tlast_reg3 <= axi_dma_tlast_reg2;
      end if;
    end if;
  end process;

end Behavioral;