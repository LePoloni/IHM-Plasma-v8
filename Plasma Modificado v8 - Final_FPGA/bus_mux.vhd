---------------------------------------------------------------------
-- TITLE: Bus Multiplexer / Signal Router
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 2/8/01
-- FILENAME: bus_mux.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    This entity is the main signal router.  
--    It multiplexes signals from multiple sources to the correct location.
--    The outputs are as follows:
--       a_bus        : goes to the ALU
--       b_bus        : goes to the ALU
--       reg_dest_out : goes to the register bank
--       take_branch  : goes to pc_next

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 12/7/16
-- MODIFICADO: 30/11/16 - Substitui use work.mlite_pack.all;
--	por use work.mlite_pack_mod.all;
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;

entity bus_mux is
   port(imm_in       : in  std_logic_vector(15 downto 0);	--Valor do imedidato
        reg_source   : in  std_logic_vector(31 downto 0);	--Valor de rs
        a_mux        : in  a_source_type;							--Seleciona a entrada para saída a_out (std_logic_vector(1 downto 0))
        a_out        : out std_logic_vector(31 downto 0);	--Define a entrada 'a' da ULA (alu, shifter e mult)

        reg_target   : in  std_logic_vector(31 downto 0);	--Valor de rt
        b_mux        : in  b_source_type;							--Seleciona a entrada para saída a_out (std_logic_vector(1 downto 0))
        b_out        : out std_logic_vector(31 downto 0);	--Define a entrada 'b' da ULA (alu, shifter e mult)

        c_bus        : in  std_logic_vector(31 downto 0);	--Saída da ULA (alu, shifter e mult)
        c_memory     : in  std_logic_vector(31 downto 0);	--Dado lido da memória RAM
        c_pc         : in  std_logic_vector(31 downto 2);	--PC atual
        c_pc_plus4   : in  std_logic_vector(31 downto 2);	--PC atual + 4
        c_mux        : in  c_source_type;							--Seleciona a entrada para saída reg_dest_out (std_logic_vector(2 downto 0))
        reg_dest_out : out std_logic_vector(31 downto 0);	--Define o valor do regisrador rd do banco de registradores

        branch_func  : in  branch_function_type;				--Define o tipo de teste para definição se ocorrerá desvio
        take_branch  : out std_logic);								--Flag que sinaliza a necessidade de desvio
end; --entity bus_mux

architecture logic of bus_mux is
begin

--Determine value of a_out
--Processo sensível a todos seus sinais de entrada
amux: process(reg_source, imm_in, a_mux, c_pc) 
begin
   --Define o valor de a_out de acordo com a_mux
	case a_mux is
	--Registrador origem rs
   when A_FROM_REG_SOURCE =>	--00
      a_out <= reg_source;
	--Imediato bits de 10 a 6???
   when A_FROM_IMM10_6 =>		--01
      a_out <= ZERO(31 downto 5) & imm_in(10 downto 6);
   --Valor atual do PC
	when A_FROM_PC =>				--10
      a_out <= c_pc & "00";
   --Outros casos (valor atual do PC)
	when others =>					--11
      a_out <= c_pc & "00";
   end case;
end process;

--Determine value of b_out
--Processo sensível a todos seus sinais de entrada
bmux: process(reg_target, imm_in, b_mux) 
begin
   --Define o valor de b_out de acordo com b_mux
	case b_mux is
	--Registrador alvo rt
   when B_FROM_REG_TARGET =>		--00
      b_out <= reg_target;
   --Imediato bits de 15 a 0
	when B_FROM_IMM =>				--01
      b_out <= ZERO(31 downto 16) & imm_in;
   --Imediato sinalizado bits de 15 a 0
	when B_FROM_SIGNED_IMM =>		--10
      if imm_in(15) = '0' then
         b_out(31 downto 16) <= ZERO(31 downto 16);
      else
         b_out(31 downto 16) <= "1111111111111111";
      end if;
      b_out(15 downto 0) <= imm_in;
   --Imediato x4???
	when B_FROM_IMMX4 =>				--11
      if imm_in(15) = '0' then
         b_out(31 downto 18) <= "00000000000000";
      else
         b_out(31 downto 18) <= "11111111111111";
      end if;
      b_out(17 downto 0) <= imm_in & "00";
   --Outros casos (só para constar, as 4 opções estão listadas acima)
	when others =>
      b_out <= reg_target;
   end case;
end process;


--Determine value of reg_dest_out
--Processo sensível a todos os seus sinais de entrada							
cmux: process(c_bus, c_memory, c_pc, c_pc_plus4, imm_in, c_mux) 
begin
	--Define o valor de reg_dest_out e acordo com c_mux
   case c_mux is
	--Saída da ULA
   when C_FROM_ALU =>  -- | C_FROM_SHIFT | C_FROM_MULT =>	--001
      reg_dest_out <= c_bus;
   --Dado lido da memória
	when C_FROM_MEMORY =>			--010
      reg_dest_out <= c_memory;
   --Valor atual do PC
	when C_FROM_PC =>					--011
      reg_dest_out <= c_pc(31 downto 2) & "00"; 
   --Valor atual do PC + 4
	when C_FROM_PC_PLUS4 =>			--100
      reg_dest_out <= c_pc_plus4 & "00";
   --Imediato deslocado 16 bis à esquerda
	when C_FROM_IMM_SHIFT16 =>		--101
      reg_dest_out <= imm_in & ZERO(15 downto 0);
   --Outros casos (saída da ULA)
	when others =>
      reg_dest_out <= c_bus;
   end case;
end process;

--Determine value of take_branch
--Processo sensível aos registradores origem e alvo do banco de registradores e ao sinal de desvio
pc_mux: process(branch_func, reg_source, reg_target) 
   variable is_equal : std_logic;
begin
	--Verifica de origem e alvo são iguais
   if reg_source = reg_target then
		--Define a variável como 1 (verdadeiro)
      is_equal := '1';
   else
		--Define a variável como 0 (falso)
      is_equal := '0';
   end if;
	
	--Verifica a função de teste selecionado pelo bloco control
   case branch_func is
	--Desvio se <0
   when BRANCH_LTZ =>						--000
      take_branch <= reg_source(31);	--Resposta depende o msb do registrador origem
   --Desvio se <=0
	when BRANCH_LEZ =>						--001
      take_branch <= reg_source(31) or is_equal; --Resposta depende o msb do registrador origem e da igualdade (vide Obs.)
   --Desvio se =0
	when BRANCH_EQ =>							--010
      take_branch <= is_equal;			--Resposta depende da igualdade (vide Obs.)
   --Desvio se !=0
	when BRANCH_NE =>							--011
      take_branch <= not is_equal;		--Resposta depende da igualdade (vide Obs.)
   --Desvio se >=0
	when BRANCH_GEZ =>						--100
      take_branch <= not reg_source(31);	--Resposta depende o msb do registrador origem
   --Desvio se >0
	when BRANCH_GTZ =>						--101
      take_branch <= not reg_source(31) and not is_equal;	--Resposta depende o msb do registrador origem e da igualdade (vide Obs.)
   --Força desvio
	when BRANCH_YES =>						--110
      take_branch <= '1';
   --Outros casos (BRANCH_NO = 111)
	when others =>
      take_branch <= '0';
   end case;
	--Obs.: provavelmente quando é um teste que envolva o valor 0, o registador target selecionado seja $0 que é sempre igual a 0
end process;

end; --architecture logic
