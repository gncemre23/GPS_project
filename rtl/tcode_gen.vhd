library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
entity tcode_gen is
  port (
    reset_n : in std_logic;
    clk     : in std_logic;

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
  signal tcode_e : signed(16 downto 0);
  signal tcode_l : signed(16 downto 0);
  signal tcode_p : signed(16 downto 0);
  signal tcode   : signed(16 downto 0);
  signal tcode_u : std_logic_vector(16 downto 0);
  signal tcode_u_1 : std_logic_vector(5 downto 0);
  signal tcode_u_2 : std_logic_vector(5 downto 0);
  type state_fsm is (
    INIT,
    E_GEN,
    L_GEN,
    P_GEN
  );

  signal state : state_fsm := INIT;

begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        tcode_e <= (others => '0');
        tcode_l <= (others => '0');
        tcode_p <= (others => '0');
        state   <= INIT;
      else
        case state is
          when INIT =>
            if (rem_code_valid = '1' and code_phase_valid = '1') then
              state   <= E_GEN;
              tcode_e <= signed(rem_code_phase) - 500;
              tcode_l <= signed(rem_code_phase) + 500;
              tcode_p <= signed(rem_code_phase);
              tcode   <= (others => '0');
            end if;
          when E_GEN =>
            tcode_e <= tcode_e + 1;
            tcode_l <= tcode_l;
            tcode_p <= tcode_p;
            state   <= L_GEN;
            tcode   <= tcode_e + 1;
          when L_GEN =>
            tcode_l <= tcode_l + 1;
            tcode_e <= tcode_e;
            tcode_p <= tcode_p;
            state   <= P_GEN;
            tcode   <= tcode_l + 1;
          when P_GEN =>
            tcode_p <= tcode_p + 1;
            tcode_e <= tcode_e;
            tcode_l <= tcode_l;
            tcode   <= tcode_p + 1;
            if (done = '1') then
              state <= INIT;
            else
              state <= E_GEN;
            end if;

          when others =>
            tcode_p <= tcode_p;
            tcode_e <= tcode_e;
            tcode_l <= tcode_l;
            tcode   <= tcode_p;
        end case;
      end if;
    end if;
  end process;

  -- For avoiding fixed point operation all the values (rem_code_phase, code_phase_step) multiplied by 1000
  process (tcode, code_phase_valid, rem_code_valid, done)
  begin
    if (tcode < 0) then
      t_code_out <= (others => '0');
    else
      -- x/1000 aprox x/2^10 + x/2^15 (ceiling)
      tcode_u <= std_logic_vector(unsigned(tcode));
      tcode_u_1 <= "00000" & tcode_u(15);
      tcode_u_2 <= tcode_u(15 downto 0);
      t_code_out <=  std_logic_vector(unsigned(tcode_u_1) + unsigned(tcode_u_2));
    end if;
    if (state /= INIT) then
        t_code_valid <= (code_phase_valid and rem_code_valid) and not(done);
    else
        t_code_valid <= '0';
    end if;
 

  end process;

end Behavioral;