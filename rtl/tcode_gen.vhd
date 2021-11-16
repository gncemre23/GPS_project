library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
entity tcode_gen is
  generic (
    SAMPLE_COUNT  : integer := 53000;
    FRQ_BIN_COUNT : integer := 54
  );
  port (
    reset_n : in std_logic;
    clk     : in std_logic;

    --0: Early 1: Late 2 :promt 3: promt
    mode : in std_logic_vector(1 downto 0);

    code_phase_step  : in std_logic_vector(15 downto 0);
    code_phase_valid : in std_logic;

    rem_code_phase : in std_logic_vector(15 downto 0);
    rem_code_valid : in std_logic;

    done : in std_logic;

    t_code_out   : out std_logic_vector(10 downto 0);
    t_code_valid : out std_logic

  );
end tcode_gen;
architecture Behavioral of tcode_gen is
  signal tcode : signed(15 downto 0);

  type state_fsm is (
    INIT,
    GO
  );

  signal state : state_fsm := INIT;

begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        tcode <= (others => '0');
        state <= INIT;
      else

        if (state = INIT) then
          if (rem_code_valid = '1' and code_phase_valid = '1') then
            if (mode = "00") then
              tcode <= signed(rem_code_phase) - 500;
            elsif (mode = "01") then
              tcode <= signed(rem_code_phase) + 500;
            else
              tcode <= signed(rem_code_phase);
            end if;
            state <= GO;
          else
            tcode <= tcode;
            state <= state;
          end if;
        elsif (done = '0') then
          tcode <= tcode + 500;
          state <= GO;
        else
          tcode <= tcode;
          state <= INIT;
        end if;
      end if;
    end if;
  end process;

  -- For avoiding fixed point operation all the values (rem_code_phase, code_phase_step) multiplied by 1000
  process (tcode, code_phase_valid, rem_code_valid, done)
  begin
    if(tcode < 0) then
        t_code_out <= (others => '0');
    else
        -- x/1000 aprox x/2^10 + x/2^15 (ceiling)
        t_code_out <= std_logic_vector(tcode(15) + tcode(15 downto 10));
    end if;

    t_code_valid <= (code_phase_valid & rem_code_valid & state) & not(done) ;
  end process;

end Behavioral;