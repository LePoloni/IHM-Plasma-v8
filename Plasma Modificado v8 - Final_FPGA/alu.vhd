---------------------------------------------------------------------
-- TITLE: Arithmetic Logic Unit
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 2/8/01
-- FILENAME: alu.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Implements the ALU.

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 8/7/16
-- MODIFICADO: 30/11/16 - Substitui use work.mlite_pack.all;
--	por use work.mlite_pack_mod.all;	
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;

entity alu is
   generic(alu_type  : string := "DEFAULT");
   
	port(a_in         : in  std_logic_vector(31 downto 0);
        b_in         : in  std_logic_vector(31 downto 0);
        alu_function : in  alu_function_type;					--std_logic_vector(3 downto 0); mlite_pack.vhd
        c_alu        : out std_logic_vector(31 downto 0));
		  
end; --alu

architecture logic of alu is
   signal do_add    : std_logic;
   signal sum       : std_logic_vector(32 downto 0);			--Possui 33 bits para armazenar o sinal ou carry!!!
   signal less_than : std_logic;
begin

   do_add <= '1' when alu_function = ALU_ADD else '0';							--Se ALU_ADD do_add=1 senão do_add=0
   sum <= bv_adder(a_in, b_in, do_add);												--bv_adder faz soma ou subtração dependendo de do_add
   
	--Se a_in(31) = b_in(31) - less_than = sum(32) ???
	--Se alu_function = ALU_LESS_THAN - less_than = sum(32) 
	--bit 32 será o sinal da subtração a_in - b_in realizada na instrução anterior
	less_than <= sum(32) when a_in(31) = b_in(31) or alu_function = ALU_LESS_THAN 
                else a_in(31);

   GENERIC_ALU: if alu_type = "DEFAULT" generate
      c_alu <= sum(31 downto 0) when alu_function=ALU_ADD or							--Add
                                alu_function=ALU_SUBTRACT else							--Sub --> negative = 0 - ? = -?
               ZERO(31 downto 1) & less_than when alu_function=ALU_LESS_THAN or 	--Less_than
                                alu_function=ALU_LESS_THAN_SIGNED else
               a_in or  b_in    when alu_function=ALU_OR else							--Or
               a_in and b_in    when alu_function=ALU_AND else							--And
               a_in xor b_in    when alu_function=ALU_XOR else							--Xor --> not = 1 Xor ? = /?
               a_in nor b_in    when alu_function=ALU_NOR else							--Nor
               ZERO;																					--Zero para as demais (ALU_NOTHING)
   end generate;

   AREA_OPTIMIZED_ALU: if alu_type /= "DEFAULT" generate
      c_alu <= sum(31 downto 0) when alu_function=ALU_ADD or 
		                          alu_function=ALU_SUBTRACT else (others => 'Z');
      c_alu <= ZERO(31 downto 1) & less_than when alu_function=ALU_LESS_THAN or 
		                          alu_function=ALU_LESS_THAN_SIGNED else 
										  (others => 'Z');
      c_alu <= a_in or  b_in    when alu_function=ALU_OR else (others => 'Z');
      c_alu <= a_in and b_in    when alu_function=ALU_AND else (others => 'Z');
      c_alu <= a_in xor b_in    when alu_function=ALU_XOR else (others => 'Z');
      c_alu <= a_in nor b_in    when alu_function=ALU_NOR else (others => 'Z');
      c_alu <= ZERO             when alu_function=ALU_NOTHING else (others => 'Z');
   end generate;
    
end; --architecture logic

