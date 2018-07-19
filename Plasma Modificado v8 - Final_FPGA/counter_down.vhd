---------------------------------------------------------------------
-- TITLE: Contador Decrescente
-- AUTHOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATE CREATED: 29/03/17
-- FILENAME: couunter_down.vhd
-- PROJECT: Plasma CPU Modificado v5
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Parte do Microkernel.
--		Contador decrescente para tempo de sleep ou yield de tarefas.
-- MODELO DO TCB:
--		Address
--		3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
--		1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
--		Value          |               |               |
--		0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 t t t t t x r r r r r 0 0
--		Legend
--		t - número da tarefa
--		r - registrador salvo
--    x - (0) faixa de registradores, (1) faixa para outros parâmetros

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- MOVIFICADO:
-- xx/xx/17 - xxxx
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;
--use ieee.numeric_std.all;		--Novidade
use IEEE.STD_LOGIC_ARITH.ALL;
use ieee.std_logic_unsigned.all;	--Converte vetor sem sinal para inteiro

entity counter_down is
	port(	clk          			: in std_logic; --tick do escalonador
			reset			     		: in std_logic;
         load                 : in std_logic; 
         sleep                : in std_logic_vector (15 downto 0);
			done                 : out std_logic := '1';
         cnt_out              : out std_logic_vector (15 downto 0) := (others => '0')	--para teste
		);
end; --entity counter_down

architecture logic of counter_down is
	signal cnt : INTEGER RANGE 0 TO 65535; 
	
begin  --architecture
	--cnt_out <= std_logic_vector(to_unsigned(cnt, cnt_out'length)); 
   cnt_out <= conv_std_logic_vector(cnt,16);
	process (clk, reset, cnt, load, sleep) 
   begin 
		if (reset = '1') then
			cnt <= 0;
			done <= '1';
		elsif (load = '1') then 						--load ativo
			--cnt <= to_integer(unsigned(sleep));	--converte vetor para inteiro
			cnt <= conv_integer(sleep);				--converte vetor para inteiro
			done <= '0';
		elsif (rising_edge(clk)) then 
			if (cnt /= 0) then
				cnt <= cnt - 1;
				done <= '0';
			else
				done <= '1';
			end if;
		end if; 
	end process; 
end; --architecture logic