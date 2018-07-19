---------------------------------------------------------------------
-- TÍTULO: ALU, Mult e Shifter
-- AUTOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATA DE CRIAÇÃO: 15/9/16
-- FILENAME: alu_mult_shifter.vhd
-- PROJETO: Plasma Modificado
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    This entity combines the CPU core with memory and a UART.
--		Ajuste para o kit DE1-SoC da Terasic
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;

entity alu_mult_shifter is
   generic(	alu_type  		: string := "DEFAULT";
				mult_type  		: string := "DEFAULT";
				shifter_type 	: string := "DEFAULT");
   
	port(clk       	: in 	std_logic;
        reset_in  	: in 	std_logic;
		  a_in         : in 	std_logic_vector(31 downto 0);	--Valores
        b_in         : in 	std_logic_vector(31 downto 0);	--Valores
        alu_func		: in  alu_function_type;					--Função da ALU
		  mult_func 	: in 	mult_function_type;					--Tipo de operação
		  shift_func   : in  shift_function_type;					--Função de deslocamento
        c_out        : out std_logic_vector(31 downto 0);
		  pause_out 	: out std_logic);								--Operação realizada em mais de um pulso de clock (32)
																				--dessa forma consegue forçar parada de PC e outros blocos
end; --alu_mult_shifter

architecture uniao of alu_mult_shifter is
	--Sinais internos
	signal c_alu          : std_logic_vector(31 downto 0);
   signal c_mult         : std_logic_vector(31 downto 0);
   signal c_shift        : std_logic_vector(31 downto 0);
	
begin --architecture
	--Define qua c_bus corresponde a saída de um dos blocos que fazem parte da ULA
	c_out <= c_alu or c_shift or c_mult;

	u1_alu: alu 
      generic map (	alu_type 		=> alu_type)
      port map 	(	a_in         	=> a_in,
							b_in         	=> b_in,
							alu_function 	=> alu_func,
							c_alu        	=> c_alu);

	u2_mult: mult 
      generic map (	mult_type 		=> mult_type)
      port map 	(	clk       		=> clk,
							reset_in  		=> reset_in,
							a         		=> a_in,
							b         		=> b_in,
							mult_func 		=> mult_func,
							c_mult    		=> c_mult,
							pause_out 		=> pause_out);

	u3_shifter: shifter
      generic map (	shifter_type 	=> shifter_type)
      port map 	(	value        	=> b_in,
							shift_amount 	=> a_in(4 downto 0),
							shift_func   	=> shift_func,
							c_shift      	=> c_shift);				

	
							
end;

