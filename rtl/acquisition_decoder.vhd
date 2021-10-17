library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;


entity acquisition_decoder is
  port (
    --! global clock
    clk : in std_logic;
    --! axi stream input data signal 
    data_in : in std_logic_vector(1 downto 0);
    --! axi stream valid signal for data input
    data_in_valid : in std_logic;
    --! decoded outputs -1("111"),1("001"),-3("101"),3("011") 
    --! upper values are given for 3 bits for 32bit, the most signficant bits are repeated
    data_out: out std_logic_vector(15 downto 0);
    data_out_valid : out std_logic 
  );
end acquisition_decoder;
architecture Behavioral of acquisition_decoder is

signal data_out_reg : std_logic_vector(15 downto 0) := x"0000";  

begin

data_out <= data_out_reg;

process (clk)
begin
    if rising_edge(clk) then
        if data_in_valid = '1' then
            data_out_valid <= '1';
            case data_in is
                when "00" =>
                    data_out_reg <= x"0001"; --  1
                when "01" =>
                    data_out_reg <= x"FFFF"; -- -1 
                when "10" =>
                    data_out_reg <= x"0003"; --  3
                when "11" =>
                    data_out_reg <= x"FFFD"; -- -3   
                when others =>
                    data_out_reg <= x"0000";  
            end case;
        else
            data_out_valid <= '0';
            data_out_reg <= data_out_reg;
        end if;
    end if;
end process;

  
end Behavioral;