---------------------------------------------------------------------
-- TITLE: Program Counter Next Real Time (baseado no arquivo pc_next.vhd)
-- AUTHOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATE CREATED: 21/09/16
-- FILENAME: pc_next_RT.vhd
-- PROJECT: Plasma CPU Modificado core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Implements the Program Counter logic.

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 8/7/16
-- MOVIFICADO: 
--	15/09/16 - Projeto Plasma Modificado
--	21/09/16 - Criação de acoplamento com Microkernel
-- 31/11/16 - Criação de nova opção de pc_source -> FROM_MICROKERNEL
-- 			- Alteração no tratamento de forma que a sinalização criada
--				  se torna suficiente para fazer a trca de tarefas
-- 28/12/16 - O código foi limpo, deixando apenas o necessário para
--				  uso no microkernel
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;

entity pc_next_RT is
   port(clk         : in std_logic;
        reset_in    : in std_logic;
        pc_new      : in std_logic_vector(31 downto 2);	--Descarta os dois lsbs por conta de avançar de 4 em 4 bytes
        take_branch : in std_logic;
        pause_in    : in std_logic;
        opcode25_0  : in std_logic_vector(25 downto 0);	--26 bits para jump incondicional
        pc_source   : in pc_source_type;						--std_logic_vector(1 downto 0); mlite_pack.vhd
        
		  pc_future   : out std_logic_vector(31 downto 2);	--Próxima a ser executada
        pc_current  : out std_logic_vector(31 downto 2);	--Em execução
        pc_plus4    : out std_logic_vector(31 downto 2); --Em execução + 4 bytes
		  
		  --Microkernel
		  pc_RT  			: in 	std_logic_vector(31 downto 2);	--30 bits para jump desvio de tarefa
		  task_switch_RT 	: in 	std_logic);								--Força a troca de tarefa
end; --pc_next_RT

architecture logic of pc_next_RT is
   
	--Sinais definem ligações internas com IOs e são usados em processos, 
	--são atualizados apenas no final e não aceitam múltiplas atribuições
	signal pc_reg : std_logic_vector(31 downto 2);	--Quarda o valor da instrução em execução

begin

				--Processo sensível a variação de todas as entradas e sinais internos
pc_select: process(clk, reset_in, pc_new, take_branch, pause_in, 
                 opcode25_0, pc_source, pc_reg, pc_RT, task_switch_RT)
   
	--Variáveis somente podem ser declaradas em código sequencial e são locais
	variable pc_inc		: std_logic_vector(31 downto 2);
   variable pc_next		: std_logic_vector(31 downto 2);
	variable pc_next_RT	: std_logic_vector(31 downto 2);
	
begin
   pc_inc := bv_increment(pc_reg);  						--pc_reg+1 (na verdade soma 4 unidades)
	
 	--Verifica qual será a próxima instrução baseada na entrada pc_source
	case pc_source is
	when FROM_INC4 =>												--000
		pc_next := pc_inc;												--Próximo atual + 4
	when FROM_OPCODE25_0 =>										--001
		pc_next := pc_reg(31 downto 28) & opcode25_0;			--Próximo = msb atual + com 26 bits de desvio
	when FROM_BRANCH | FROM_LBRANCH =>						--010 | 011
		if take_branch = '1' then										--Se é um desvio
			pc_next := pc_new;												--Próximo = new
		else																	--Senão
			pc_next := pc_inc;												--Próximo = atual + 4
		end if;
	when FROM_MICROKERNEL =>									--100
		pc_next := pc_RT;
	when others =>													--Outros casos
		pc_next := pc_inc;												--Próximo = atual + 4
	end case;

   if pause_in = '1' then										--Se Pause = 1
      pc_next := pc_reg;											--Próximo = reg (atual)
   end if;

   if reset_in = '1' then										--Se Reset = 1
      pc_reg <= ZERO(31 downto 2);								--Reg = 0
      pc_next := pc_reg;											--Próximo = 0
   elsif rising_edge(clk) then								--Senão se ocorreu um borda de subida no clock
      pc_reg <= pc_next;											--Reg = Próximo
   end if;

	--Atualiza as saídas
   pc_future <= pc_next;										--Futuro = Próximo
   pc_current <= pc_reg;										--Atual = Reg (apesar de alterado no processo seu valor só é atualizado no final dele)
   pc_plus4 <= pc_inc;											--Plus4 = atual + 4
end process;

end; --logic
