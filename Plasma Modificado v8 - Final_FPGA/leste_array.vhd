library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;
--use ieee.numeric_std.all;
use IEEE.STD_LOGIC_ARITH.ALL;

entity leste_array is
	port(	clk          			: in std_logic;
			input2					: in std_logic_vector(1 downto 0);
			input3					: in std_logic_vector(3 downto 0);
			live						: in std_logic_vector(3 downto 0);
			state0					: out std_logic_vector(1 downto 0);
			state1					: out std_logic_vector(1 downto 0);
			state2					: out std_logic_vector(1 downto 0);
			state3					: out std_logic_vector(1 downto 0));
		
end; --entity microkernel

architecture logic of leste_array is
	--Sinais (atualizadas apenas no final dos processos)
		--Cria array para estados das tarefas (2 bits)
	--00-Suspensa, 01-Bloqueada, 10-Pronta, 11-Rodando
   type state_array is array(natural range 0 to 3) of std_logic_vector(1 downto 0);
   signal task_state : state_array;	
	
begin  --architecture
	process(input2,clk)
	begin
		if rising_edge(clk) then
			if input2 = "00" then
				for index in 0 to 3 loop
					task_state(index) <= "00";
				end loop;

			elsif input2 = "01" then
				for index in 0 to 3 loop
					if live(index) = '1' then
						task_state(index) <= "10";
					end if;
				end loop;
			
			elsif input2 = "10" then
				for index in 0 to 3 loop
					if live(index) = '1' then
						if input3(index) = '1' then
							task_state(index) <= "11";
						else
							task_state(index) <= "10";
						end if;
					end if;
				end loop;
			
			
--			elsif input2 = "11" then
				
			end if;
		end if;	
	
	end process;
	
	state0 <= task_state(0);
	state1 <= task_state(1);
	state2 <= task_state(2);
	state3 <= task_state(3);
end architecture;