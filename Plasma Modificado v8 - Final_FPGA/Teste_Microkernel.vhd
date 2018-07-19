library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;
--use ieee.numeric_std.all;
use IEEE.STD_LOGIC_ARITH.ALL;

entity Teste_Microkernel is
	port(	clk          			: in std_logic;
			reset_in     			: in std_logic;
			counter		 			: in std_logic_vector(31 downto 0);			--x Entrada de contador para definição da troca de tarefas (substituido pelo sinal de clock)
			
			--Configuração e uso do escalonador
			escalonador  			: in std_logic_vector(0 downto 0);			--Bit 0 habilita o escalonador
			tick			 			: in std_logic_vector(31 downto 0);			--Tempo do tick em pulsos de clock
			task_number	 			: in std_logic_vector(31 downto 0);			--Quantidade de tarefas
			task_live	 			: in std_logic_vector(31 downto 0);			--Vetor de tarefas (existe/não existe, máx. 32)
			task_pri7_0				: in std_logic_vector(31 downto 0); 		--Vetor de prioridade das tarefas 7~0 (4 bits por tarefa)
			task_pri15_8			: in std_logic_vector(31 downto 0); 		--Vetor de prioridade das tarefas 15~8
			task_pri23_16			: in std_logic_vector(31 downto 0); 		--Vetor de prioridade das tarefas 23~16
			task_pri31_24			: in std_logic_vector(31 downto 0); 		--Vetor de prioridade das tarefas 32~24

			--Microkernel conectado ao bloco pc_next_RT
			pc_RT  					: out std_logic_vector(31 downto 2);		--30 bits para jump desvio de tarefa
			--pc_RT  					: out std_logic_vector(29 downto 0);		--30 bits para jump desvio de tarefa SIMULAÇÂO !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			task_switch_RT 		: out std_logic;									--Força a troca de tarefa
			pc_backup_RT			: in	std_logic_vector(31 downto 2);		--30 bits com o endereço da próxima instrução sem considerar troca de tarefa
		  
			--Microkernel conectado ao bloco reg_bank_duplo_RT
			rs_index_RT       	: out  std_logic_vector(5 downto 0);		--End. fonte de dados (6 bits ao invés de 5)
			rt_index_RT       	: out  std_logic_vector(5 downto 0);		--End. fonte de ou destino de dados
			rd_index_RT       	: out  std_logic_vector(5 downto 0);		--End. destino de dados
			reg_source_out_RT 	: in 	 std_logic_vector(31 downto 0);		--Saída de dados de acordo com rs
			reg_target_out_RT 	: in   std_logic_vector(31 downto 0);		--Saída de dados de acordo com rt
			reg_dest_new_RT   	: out  std_logic_vector(31 downto 0);		--Entrada de dados de acordo com rd
			intr_enable_RT    	: in   std_logic;									--Flag de enable de interrupção
		  
			sel_bank_RT				: out  std_logic;									--Seleciona o banco utilizado pela CPU
			
			--Microkernel conectado as fontes de pause da CPU (NÃO UTILIZADO)
			pause_RT					: in std_logic;									--Sinaliza que a CPU está pausada, não trocar tarefa nesta hora	
			
			--Microkernel conectado ao bloco control
			switch_out_RT			: in std_logic;									--Sinaliza pedido de switch em atendimento
			
			--Microkernel conectado ao bloco ram_rt
			mk_address       		: out	std_logic_vector(31 downto 0);		--Microkernel - endereço da memória RAM TCB
			mk_byte_we       		: out std_logic_vector(3 downto 0);			--Microkernel - bytes para escrita na memória RAM TCB
			mk_data_w        		: out std_logic_vector(31 downto 0);		--Microkernel - dado para escrita na RAM TCB
			mk_data_r        		: in	std_logic_vector(31 downto 0);		--Microkernel - dado para leitura na RAM TCB
			
			--Saída para depuração (criado em 24/11/16)
			mk_debug					: out std_logic_vector(7 downto 0);
			
			task_state7_0			: out std_logic_vector(15 downto 0);
			task_state15_8			: out std_logic_vector(15 downto 0);
			task_state23_16		: out std_logic_vector(15 downto 0);
			task_state31_24		: out std_logic_vector(15 downto 0);
			
			task_futura				: in integer range 0 to 31 := 0;
			task_antiga				: in integer range 0 to 31 := 0;
			
			wait_flag				: out std_logic;
			
			live_flag				: out std_logic;
			
			output2					: in std_logic_vector(1 downto 0));
		
end; --entity microkernel

architecture logic of Teste_Microkernel is
	--Sinais (atualizadas apenas no final dos processos)
	signal reset   		: std_logic;
	signal tick_flag   	: std_logic;
	signal task_ativa		: integer range 0 to 31 := 0;		--Tarefa ativa
	signal input			: std_logic_vector(1 downto 0);	--tick_flag & mem_source_RT
	signal output			: std_logic_vector(2 downto 0);	--task_switch_RT & bank_switch & context_backup
	signal sel_bank		: std_logic;							--Banco selecionado
	signal pc_backup		: std_logic_vector(31 downto 0);	--Back do PC
	signal backup_init	: std_logic;							--Dispara pedido de backup de contexto para o gerenciador de contexto
	signal bank_switch	: std_logic;							--Dispara pedido de inversão dos bancos de registradores
	signal context_backup: std_logic;							--Dispara pedido de backup do contexto ao gerenciador de contexto
	signal backup_ready	: std_logic;							--Sinalização de backup pronto passado pelo gerenciador de contexto
--	signal task_futura	: integer range 0 to 31 := 0;
--	signal task_antiga	: integer range 0 to 31 := 0;
	signal pc_restore		: std_logic_vector(31 downto 0);	--Restauração do PC
	signal restore_init	: std_logic;							--Dispara pedido de restauração de contexto para o gerenciador de contexto
	signal restore_ready	: std_logic;							--Sinalização de restauração pronta passado pelo gerenciador de contexto
	signal restore_flag  : std_logic;
--	signal task_state7_0	: std_logic_vector(15 downto 0);
--	signal task_state15_8	: std_logic_vector(15 downto 0);
--	signal task_state23_16	: std_logic_vector(15 downto 0);
--	signal task_state31_24	: std_logic_vector(15 downto 0);
	signal task_next		: std_logic_vector(4 downto 0);
	signal tick_enable	: std_logic;
--	signal wait_flag		: std_logic;
	
	-- Build an enumerated type for the state machine
	type state_type is (s0, s1, s2, s3);

	-- Register to hold the current state
	signal state   : state_type;

	--Cria array para estados das tarefas (2 bits)
	--00-Suspensa, 01-Bloqueada, 10-Pronta, 11-Rodando
   type state_array is array(natural range 0 to 31) of std_logic_vector(1 downto 0);
   signal task_state : state_array;	
	
	-- Build an enumerated type for the state machine
	type state_type2 is (s0, s1, s2, s3);

	-- Register to hold the current state
	signal state_tarefas : state_type2;
	
	signal input2			: std_logic_vector(1 downto 0);	--(tick_flag and tick_enable) & escalonador(0)
--	signal output2			: std_logic_vector(1 downto 0);	--???
	--\/\/\/\/\/\/ Teste atualização de tarefas ativas (13/1/2017)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--	signal live_flag		: std_logic;
	signal task_live_old : std_logic_vector(31 downto 0);			--Vetor de tarefas (existe/não existe, máx. 32)
	--/\/\/\/\/\/\ Teste atualização de tarefas ativas (13/1/2017)
	
begin  --architecture

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--DEFINE A CONDIÇÃO INICIAL DAS TAREFAS COM BASE NOS ESTADOS DA SAÍDA
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (output2, clk, escalonador, task_live, task_ativa, task_antiga, task_state,task_live_old)
		variable index : natural := 0;
	begin
		--Ao iniciar o escalonador todas as tarefas existentes sao colocadas em estado ready
		if rising_edge(clk) then
			if output2 = "01" then
				for index in 0 to 31 loop
					--Se a tarefa existe
					if task_live(index) = '1' then
						task_state(index) <= "10";		--Estado inicial = ready (pronta)
					--Senão
					else
						task_state(index) <= "00";		--Estado inicial = suspend (suspensa)
					end if;		
				end loop;
				--\/\/\/\/\/\/ Teste atualização de tarefas ativas (13/1/2017)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				task_live_old <= task_live;
				--/\/\/\/\/\/\ Teste atualização de tarefas ativas (13/1/2017)
			elsif output2 = "10" then
----				task_state(task_ativa) <= "11";		--Tarefa ativa = running (rodando)
----				if task_ativa /= task_antiga then
----					task_state(task_antiga) <= "10";
----				end if;
--				task_state(task_futura) <= "11";		--Tarefa ativa = running (rodando) (12/1/2017)
--				task_state(task_antiga) <= "10";
--			--end if;

				for index in 0 to 31 loop
					--Se a tarefa existe
					if task_live(index) = '1' then
						if index = task_futura then
							task_state(task_futura) <= "11";
						else						
							task_state(index) <= "10";		--Estado inicial = ready (pronta)
						end if;
--					--Senão
--						task_state(index) <= "11";		--Estado inicial = ready (pronta)
--					else
--						task_state(index) <= "00";		--Estado inicial = suspend (suspensa)
					end if;		
				end loop;



			--\/\/\/\/\/\/ Teste atualização de tarefas ativas (13/1/2017)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			elsif output2 = "11" then
				--Se existe um pedido de atualização de estados
				--if live_flag = '1' then
				--if task_live /= task_live_old then
					for index in 0 to 31 loop
						--Se a tarefa existe e antes não existia
						if task_live(index) = '1' and  task_live_old(index) = '0' then
							task_state(index) <= "10";		--Estado inicial = ready (pronta)							
						--Senão, se a tarefa não existe e antes existia
						elsif task_live(index) = '0' and  task_live_old(index) = '1' then
							task_state(index) <= "00";		--Estado inicial = suspend (suspensa)
						--Senão, mantém o valor anterior
						else
							task_state(index) <= task_state(index);
						end if;
						--task_live_old(index) <= task_live(index);
					end loop;

--						--Se a tarefa existe
--						if task_live(index) = '1' then
--							task_state(index) <= "01";		--Estado inicial = ready (pronta)
--						--Senão
--						else
--							task_state(index) <= "00";		--Estado inicial = suspend (suspensa)
--						end if;	
--					end loop;

					--Atualiza o registrador de valor antigo;
					task_live_old <= task_live;
				--end if;			
			
--			elsif output2 = "00" then
--				for index in 0 to 31 loop
--					task_state(index) <= "00";		--Estado inicial = suspend (suspensa)
--				end loop;
--				--\/\/\/\/\/\/ Teste atualização de tarefas ativas (13/1/2017)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--				task_live_old <= task_live;
--				--/\/\/\/\/\/\ Teste atualização de tarefas ativas (13/1/2017)
--			
			end if;
			--/\/\/\/\/\/\ Teste atualização de tarefas ativas (13/1/2017)

	
		end if;
		
		--\/\/\/\/\/\/ Teste atualização de tarefas ativas (13/1/2017)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		if task_live /= task_live_old then
			live_flag <= '1';
		else
			live_flag <= '0';
		end if;
		--/\/\/\/\/\/\ Teste atualização de tarefas ativas (13/1/2017)
		
		task_state7_0		<= task_state(7) & task_state(6) & task_state(5) & task_state(4) & 
									task_state(3) & task_state(2) & task_state(1) & task_state(0);
		task_state15_8		<= task_state(15) & task_state(14) & task_state(13) & task_state(12) & 
									task_state(11) & task_state(10) & task_state(9) & task_state(8);						
		task_state23_16	<= task_state(23) & task_state(22) & task_state(21) & task_state(20) & 
									task_state(19) & task_state(18) & task_state(17) & task_state(16);	
		task_state31_24	<= task_state(31) & task_state(30) & task_state(29) & task_state(28) & 
									task_state(27) & task_state(26) & task_state(25) & task_state(24);	
	end process;
--		task_state7_0		<= task_state(7) & task_state(6) & task_state(5) & task_state(4) & 
--									task_state(3) & task_state(2) & task_state(1) & task_state(0);
--		task_state15_8		<= task_state(15) & task_state(14) & task_state(13) & task_state(12) & 
--									task_state(11) & task_state(10) & task_state(9) & task_state(8);						
--		task_state23_16	<= task_state(23) & task_state(22) & task_state(21) & task_state(20) & 
--									task_state(19) & task_state(18) & task_state(17) & task_state(16);	
--		task_state31_24	<= task_state(31) & task_state(30) & task_state(29) & task_state(28) & 
--									task_state(27) & task_state(26) & task_state(25) & task_state(24);	

end architecture;