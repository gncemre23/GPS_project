library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
entity tlast_module is
  generic (
    DWIDTH : integer := 32;
    -- as byte
    TX_SIZE : integer := 512
  );
  port (
    reset_n   : in std_logic;
    clk     : in std_logic;
    t_valid : in std_logic;
    t_ready : in std_logic;
    t_last  : out std_logic

  );
end tlast_module;
architecture Behavioral of tlast_module is
  type State_Type is (INIT, TRANMISSION);
  signal state_next, state_reg : State_Type;
  signal cnt_next, cnt_reg     : unsigned(31 downto 0);
begin

  ------------------- The state machine -----------------------
  -- sequential part
  process (clk)
  begin
    if (rising_edge(clk)) then
      -- synchronous reset
      if (reset_n = '0') then
        state_reg <= INIT;
        cnt_reg   <= (others => '0');
      else
        state_reg <= state_next;
        cnt_reg   <= cnt_next;
      end if;
    end if;
  end process;

  -- combinatorial part
  process (state_reg, cnt_reg, t_valid)
  begin
    --default assignments
    state_next <= state_reg;
    cnt_next   <= cnt_reg;
    t_last     <= '0';

    case state_reg is
      when INIT =>
        cnt_next   <= to_unsigned(TX_SIZE - 2*DWIDTH/8, 32);
        state_next <= TRANMISSION;

      when TRANMISSION =>

        if (t_valid = '1' and t_ready = '1') then
          if (signed(cnt_next) > 0) then
            cnt_next <= cnt_reg - to_unsigned(DWIDTH/8, 5);
          else
            cnt_next   <= to_unsigned(TX_SIZE - 2*DWIDTH/8, 32);
            t_last     <= '1';
          end if;

        end if;

    end case;
  end process;

end Behavioral;