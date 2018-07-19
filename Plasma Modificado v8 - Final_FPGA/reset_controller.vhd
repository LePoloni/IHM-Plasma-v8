---------------------------------------------------------------------
-- TITLE: Reset Controller
-- AUTHOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATE CREATED: 15/09/16
-- FILENAME: reset_controller.vhd
-- PROJECT: Plasma Modificado
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Implements the 32-bit shifter unit.

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 
-- MOVIFICADO: 2/11/2016
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.mlite_pack_mod.all;

entity reset_controller is
		port(	clk          : in std_logic;
				reset_in     : in std_logic;
				reset_out    : out std_logic);
end; --entity reset_controller

architecture logic of reset_controller is
	signal reset_reg      : std_logic_vector(3 downto 0);

begin
	--Define reset quando a entrada de reset estiver setada ou reset_reg != 1111
	--Pelo que entendi reset_reg funciona como um delay de 15 pulsos de clock assim que a condição de reset
	--é removida. Contador 0.. 15 acionado na borda de descida do sinal de reset.
   reset_out <= '1' when reset_in = '1' or reset_reg /= "1111" else '0';
	
	--synchronize reset and interrupt pins
   intr_proc: process(clk, reset_in, reset_reg)
   begin
		--Se a entrada de reset = 1
      if reset_in = '1' then
			--Zera o contador reset_reg
         reset_reg <= "0000";
		--Senão se ocorrer uma borda de subida do clock
      elsif rising_edge(clk) then
			--Se o contador ainda não atingiu 1111
         if reset_reg /= "1111" then
				--Incrementa o contador
            reset_reg <= reset_reg + 1;
         end if;
      end if;
   end process;
	
end; --architecture logic