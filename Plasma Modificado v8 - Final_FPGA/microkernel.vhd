---------------------------------------------------------------------
-- TITLE: Microkernel
-- AUTHOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATE CREATED: 2/11/16
-- FILENAME: microkernel.vhd
-- PROJECT: Plasma CPU Modificado v4
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Composto pelos blocos Escalonar e Gerenciador de Contexto.
--		Por enquanto apenas força os sinais de saída. Aqui devem
--		ser incorporados os Escalonar e Gerenciador de Contexto que
--		serão criados como duas entidades independentes.

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- MOVIFICADO:  Leandro Poloni Dantas
-- 05/11/16 - Incluido ieee.numeric_std.all
-- 23/11/16 - Criação de processo para alternar bancos
-- 24/11/16 - Incluido o sinal mk_debug no Microkernel
-- 02/12/16 - Preparação de integração com Gerenciador de Contexto
-- 02/12/16 - Removi o pause nos incrementos do contador de tick,
--            ele poderia causar jitter na troca de tarefas
-- 07/12/16 - Ajuste do tempo para solitar restore dos registradores,
--				  ele foi aumentado em 34 para 37 ticks.
--				- Atualização de pc_RT depende de borda de subida em restore_flag,
--				  antes o nível alto já era suficiente
-- 20/12/16 - Alterada a quantidades de clocks antes do tick_flag para ativar
--				  o restore_flag (linha ~197)
-- 23/12/16 - Defini o valor inicial para task_antiga e task_futura = 0
-- 28/12/16 - Ajustei pc_RT para para utilizar o valor de PC salvo ao
--				  executar uma troca de tarefa
--				- Apaguei trechos de código obsoletos
--				- Removida a entrada mem_source_RT		: in mem_source_type; não foi usada pelo Microkernel
-- 30/12/16 - Diminui o número de bits do sinal escalonador do microkernel
--				  para apenas 1 bit (vetor com 1 bit), a intenção é deixar a
--				  síntese e a compilação mais rápidas
-- 10/01/17 - Início da integração com o bloco escalonador
-- 11/01/17 - Conclusão da integração e primeiros testes
-- 12/01/17 - Ajustes no sinal de disparo de incrementos do tempo de espera das
--				  tarefas no escalonador (wait_flag). Esse sinal deve ocorrer fora da
--				  área de transição dos sinais task_ativa, task_futura e task_antiga,
--				  ou seja, antes do restore_flag e após o tick_flag
-- 17/01/17 - Funcionamento dinâmico de ativação de tarefas foi corrigido, antes
--				  quando as tarefas superiores a tarefa 0 começavam desligadas a
--				  máquina de estados não saia do estado "01" o que fazia que somente
--				  a tarefa 0 fosse executada. O erro estava na variável de entrada
--				  input2 que levava em consideração o sinal tick_enable.
-- 29/03/17 - Incluido o registrador task_sleep para sleep e yield de tarefas
-- 03/05/17 - Começei as alterações na lógica (máquinas de estados) para trabalhar
--				  com sleep e yield e seus contadores.
-- 12/05/17 - Implementei o MUX para controle de tarefa por sleep_yield
--          - Alterei o como de carga do sianl de load dos contadores de sleep (DEMUX)
--          - Implementei mais um contador de sleep (u5_counter_down_2)
--				- Completei os sinais necessários para as trocas de estados das funçãoes
--				  de sleep e yield.
-- 13/05/17 - Mudei o empo para o restore_flag de 68 para 69 clocks, isso evita que
--				  o restore_ready ocorre junto com o tick_flag e comprometa a definição
--				  do novo pc_RT (pc_restore).
--				- Coloquei o a restauração do pc_RT na borda de descida o sinal
--				  restore_ready ao invés de junto com a borda de descida do
--				  task_switch_RT, pelo mesmo motivo da lateração anterior.
--				- O sinal sleep_yield está recebendo o valor invertido com base no sinal
--				  done de cada contador, isso foi corrigido.
--				- Alterei os sinais enviados para depuração (mk_debug).
--	17/05/17 - Corrigi bug no state_motor estado 9 para 6 estava como condição
--				  restore_ready ao invés de backup_ready.
-- 21/05/17 - Criada máquina de estados para captura correta de PC para backup
--				  considerenado os pedidos de Sleep e Yield.
--				- Corrigido a borda de leitura do valor de pc_restore passado pelo
--				  context_manager, estava na borda de descida ao invés da de subida.
-- 11/07/17 - Incluido contadores para controle de sleep e yiled das tarefas de
--				  3 a 8 (U6~U11).
-- 23/09/17 - Alterada a função do registrador task_number, passou em entrada
--				  com indicação da quantidade de tarefas ativas, definido pelo usuário e
--				  sem nenhuma aplicação prática, para saída com a indicação da tarefa
--				  ativa em vetor binário.
-- 23/01/18 - O processo auxiliar para evitar trocas desnecessárias de tarefas
--				  (linha ~480) precisou ser dividido em 2 por conta dele trabalhar 
--				  com as duas bordas do clock e o Encounter (Cadence) não suportar
--				  processos com essas características.
--				- O processo que define como os backup são deitos
--				  (linha ~789) precisou ser dividido em 2 por conta dele trabalhar 
--				  com as duas bordas do clock e o Encounter (Cadence) não suportar
--				  processos com essas características.
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;
--use ieee.numeric_std.all;
use IEEE.STD_LOGIC_ARITH.ALL;

entity microkernel is
	port(	clk          			: in std_logic;
			reset_in     			: in std_logic;
			counter		 			: in std_logic_vector(31 downto 0);			--x Entrada de contador para definição da troca de tarefas (substituido pelo sinal de clock)
			
			--Configuração e uso do escalonador
			escalonador  			: in std_logic_vector(0 downto 0);			--Bit 0 habilita o escalonador
			tick			 			: in std_logic_vector(31 downto 0);			--Tempo do tick em pulsos de clock
			task_number	 			: out std_logic_vector(31 downto 0);		--Tarefa ativa (era entrada com a quantidade de tarefas)
			task_live	 			: in std_logic_vector(31 downto 0);			--Vetor de tarefas (existe/não existe, máx. 32)
			task_pri7_0				: in std_logic_vector(31 downto 0); 		--Vetor de prioridade das tarefas 7~0 (4 bits por tarefa)
			task_pri15_8			: in std_logic_vector(31 downto 0); 		--Vetor de prioridade das tarefas 15~8
			task_pri23_16			: in std_logic_vector(31 downto 0); 		--Vetor de prioridade das tarefas 23~16
			task_pri31_24			: in std_logic_vector(31 downto 0); 		--Vetor de prioridade das tarefas 32~24
			task_sleep				: in std_logic_vector(31 downto 0);			--Tempo de sleep ou yield da tarefa atual
			
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
			intr_enable_RT    	: in   std_logic;									--x Flag de enable de interrupção
		  
			sel_bank_RT				: out  std_logic;									--Seleciona o banco utilizado pela CPU
			
			--Microkernel conectado as fontes de pause da CPU (NÃO UTILIZADO)
			pause_RT					: in std_logic;									--x Sinaliza que a CPU está pausada, não trocar tarefa nesta hora	
			
			--Microkernel conectado ao bloco control
			switch_out_RT			: in std_logic;									--Sinaliza pedido de switch em atendimento
			
			--Microkernel conectado ao bloco ram_rt
			mk_address       		: out	std_logic_vector(31 downto 0);		--Microkernel - endereço da memória RAM TCB
			mk_byte_we       		: out std_logic_vector(3 downto 0);			--Microkernel - bytes para escrita na memória RAM TCB
			mk_data_w        		: out std_logic_vector(31 downto 0);		--Microkernel - dado para escrita na RAM TCB
			mk_data_r        		: in	std_logic_vector(31 downto 0);		--Microkernel - dado para leitura na RAM TCB
			
			--Saída para depuração (criado em 24/11/16)
			--Alterado para 16 bits (21/05/17)
			mk_debug					: out std_logic_vector(15 downto 0));
		
end; --entity microkernel

architecture logic of microkernel is
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
	signal task_futura	: integer range 0 to 31 := 0;
	signal task_antiga	: integer range 0 to 31 := 0;
	signal pc_restore		: std_logic_vector(31 downto 0);	--Restauração do PC
	signal restore_init	: std_logic;							--Dispara pedido de restauração de contexto para o gerenciador de contexto
	signal restore_ready	: std_logic;							--Sinalização de restauração pronta passado pelo gerenciador de contexto
	signal restore_flag  : std_logic;
	signal task_state7_0	: std_logic_vector(15 downto 0);
	signal task_state15_8	: std_logic_vector(15 downto 0);
	signal task_state23_16	: std_logic_vector(15 downto 0);
	signal task_state31_24	: std_logic_vector(15 downto 0);
	signal task_next		: std_logic_vector(4 downto 0);
	signal tick_enable	: std_logic;
	signal wait_flag		: std_logic;
	signal counter_done	: std_logic_vector(31 downto 0);	--Vetor com o status dos contadores de sleep
	signal atualiza_task_ativa	: std_logic; --17/05/17
	signal pc_backup_temp	: std_logic_vector(31 downto 0);	--17/05/17 Back do PC 1o nível 
	
	-- Build an enumerated type for the state machine
	type state_type3 is (s0, s1, s2, s3, s4, s5, s6, s7, s8, s9);
	-- Register to hold the current state
	signal state_motor   : state_type3;
	
	signal input3			: std_logic_vector(6 downto 0);
	signal output3			: std_logic_vector(4 downto 0); --17/05/17 eram 4 bits agora são 5 bits
	
	-- Build an enumerated type for the state machine
	type state_type4 is (s0, s1, s2, s3, s4);
	-- Register to hold the current state
	signal state_pc_backup   : state_type4;
	
	signal input4			: std_logic_vector(1 downto 0);
	signal output4			: std_logic_vector(1 downto 0); --17/05/17

	--Cria array para estados das tarefas (2 bits)
	--00-Suspensa, 01-Bloqueada, 10-Pronta, 11-Rodando
   type state_array is array(natural range 0 to 31) of std_logic_vector(1 downto 0);
   signal task_state : state_array;	
	
	-- Build an enumerated type for the state machine
	type state_type2 is (s0, s1, s2, s3);
	-- Register to hold the current state
	signal state_tarefas : state_type2;
	
	signal input2			: std_logic_vector(1 downto 0);	--(tick_flag and tick_enable) & escalonador(0)
	signal output2			: std_logic_vector(1 downto 0);	--???
	--\/\/\/\/\/\/ Teste atualização de tarefas ativas (13/1/2017)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	signal live_flag		: std_logic;
	signal task_live_old : std_logic_vector(31 downto 0);			--Vetor de tarefas (existe/não existe, máx. 32)
	--/\/\/\/\/\/\ Teste atualização de tarefas ativas (13/1/2017)
	
	signal load_sleep_flag: std_logic_vector(31 downto 1);	--Flags para load de sleep ou yield das trefas de 1 a 31
	signal sleep_yield	: std_logic;
	
	signal debug_state_motor : std_logic_vector(3 downto 0);
	signal debug_state_pc_backup : std_logic_vector(2 downto 0);
	signal debug_state_tarefas : std_logic_vector(1 downto 0);
	
	
begin  --architecture
	--Componentes
	u1_reset_controller: reset_controller
	port map (
		clk       => clk,
		reset_in  => reset_in,
		reset_out => reset);

	u2_context_manager: context_manager
	port map (
		clk,
		reset,

		--Microkernel conectado ao bloco reg_bank_duplo (por enquanto ligação direta)
		rs_index_RT,
		rt_index_RT,
		rd_index_RT,
		reg_source_out_RT,
		reg_target_out_RT,
		reg_dest_new_RT,
	  
		--Microkernel conectado ao bloco ram_rt
		mk_address,
		mk_byte_we,
		mk_data_w,
		mk_data_r,	
		
		--Microkernel sinais internos
		task_futura,
		task_antiga,
		backup_init,
		backup_ready,
		pc_backup,
		restore_init,
		restore_ready,
		pc_restore
		
		--Saída para depuração (criado em 24/11/16)
		--mk_debug,			
		--q	
	);
	
	u3_scheduler: scheduler
	port map(	
		clk,
		reset,
		wait_flag,
--		wait_flag => restore_init,
		--Configuração e uso do escalonador
		task_live => task_live,
		
		--Informações para uso do algoritmo
		--Priodidade (3 bits): níveis de 0 a 7 (o é a maior prioridade)
		task_pri7_0 => task_pri7_0,
		task_pri15_8 => task_pri15_8,
		task_pri23_16 => task_pri23_16,
		task_pri31_24 => task_pri31_24,
		--Estados (2 bits): 0-Suspensa, 1-Bloqueada, 2-Pronta, 3-Rodando
		task_state7_0 => task_state7_0,
		task_state15_8 => task_state15_8,
		task_state23_16 => task_state23_16,
		task_state31_24 => task_state31_24,
		
		--Próxima tarefa
		task_next => task_next
	);
	
	u4_counter_down_1: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(1)),
      load		=> load_sleep_flag(1),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(1)
      --cnt_out		--para teste
	);
	
	u5_counter_down_2: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(2)),
      load		=> load_sleep_flag(2),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(2)
      --cnt_out		--para teste
	);
	
	u6_counter_down_3: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(3)),
      load		=> load_sleep_flag(3),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(3)
      --cnt_out		--para teste
	);

	u7_counter_down_4: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(4)),
      load		=> load_sleep_flag(4),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(4)
      --cnt_out		--para teste
	);
	
	u8_counter_down_5: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(5)),
      load		=> load_sleep_flag(5),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(5)
      --cnt_out		--para teste
	);
	
	u9_counter_down_6: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(6)),
      load		=> load_sleep_flag(6),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(6)
      --cnt_out		--para teste
	);
	
	u10_counter_down_7: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(7)),
      load		=> load_sleep_flag(7),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(7)
      --cnt_out		--para teste
	);
	
	u11_counter_down_8: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(8)),
      load		=> load_sleep_flag(8),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(8)
      --cnt_out		--para teste
	);
	
	--Por enquanto apenas dois contadores ativos
--	counter_done(0) <= '1';
--	counter_done(31 downto 3) <= ones(31 downto 3);
	
	--8 tarefas com sleep_yield
	counter_done(0) <= '1';
	counter_done(31 downto 9) <= ones(31 downto 9);
	
	--Código
	sel_bank_RT 			<= sel_bank;	--0/1 inverte o banco utilizado pela CPU
	
	--Microkernel conectado as fontes de pause da CPU
	--pause_RT					<= open;
			
	--Microkernel conectado ao bloco mem_ctrl
	--mem_source_RT			<= open;
	
	--Saída para depuração (criado em 24/11/16)
	--mk_debug					<= output2 & switch_out_RT & restore_ready & restore_flag & tick_flag & escalonador(0) & sel_bank;
	--Saída para depuração (criado em 13/05/17)
	mk_debug					<= --"00" & --bit 7 e 6
									--output3(2) & --task_switch_RT + --bit 5
									--bank_switch & --bit 5
									--load_sleep_flag(2) &
									--tick_flag & --bit 4
									--sleep_yield	& --bit 4
									--load_sleep_flag(1) &
									
									--(backup_init OR backup_ready) & --bit 4
									--(restore_init OR restore_ready) & --bit 3
									--restore_init & --bit 2
									--tick_enable & --bit 1 
									--escalonador(0); --bit 0 OK
									--load_sleep_flag(1) & --bit 3
									--task_state(1) & --bit 2 e 1
									--counter_done(1); --bit 0
									--debug_state_motor;
									--conv_std_logic_vector(task_ativa,2);
									--task_state(0)&
									--counter_done(2)&
									--counter_done(1)&
									
									--atualiza_task_ativa & --task_switch_RT &
									--backup_init &
									
									--output2 &
									--task_next(1 downto 0) &
									
									--task_next(1 downto 0);
									--task_state(1);
									--counter_done(1) &
									--task_state7_0(3 downto 2);
--									debug_state_tarefas &						--15-14
--									debug_state_pc_backup &						--13-11
--									debug_state_motor	&							--10-7
									--pc_backup_RT(10 downto 2) &				---15-7
									--pc_backup(10 downto 2) &					---15-7
									restore_ready &								--15
									pc_restore(9 downto 2) &					--14-7
									backup_init &									--6								
									conv_std_logic_vector(task_futura,2) &	--5-4 
									conv_std_logic_vector(task_ativa,2) &	--3-2
									--conv_std_logic_vector(task_antiga,2);	--1-0
									task_next(1 downto 0);						--1-0
		
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--SINALIZAÇÃO DE FIM DE TIME SLICE (DISPARA MÁQUINA DE ESTADOS) -> tick_flag e restore_flag
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	time_slice: process(clk, reset, escalonador(0), tick)
		variable   cnt		   : integer range 0 to (2**30) - 1;
	begin
		if reset = '1' or escalonador(0) = '0' then
			-- Reset the counter to 0
			cnt := 0;
			tick_flag <= '0';
			task_number <= ZERO(31 downto 0);	--Se o escalonar não está ativa
		elsif rising_edge(clk) then
			-- Increment the counter if counting is enabled			   
			cnt := cnt + 1;
	
			--Se chegou no final do time slice (cnt = tick)
			if tick = conv_std_logic_vector(cnt,32) then
				cnt := 0;
				tick_flag <= '1'; --Início da troca de tarefas
			else
				tick_flag <= '0';
			end if;
			
			-- Se faltam n incrementos para chegar no tick (cnt = (tick-n))
			--if tick = conv_std_logic_vector(cnt+68,32) then
			if tick = conv_std_logic_vector(cnt+69,32) then		--13/05/17 68 cloks para restauração 
				restore_flag <= '1';	--Início da restauração dos registradores
			else
				restore_flag <= '0';
			end if;
			
			-- Se faltam n incrementos para chegar no tick (cnt = (tick-n))
			if tick = conv_std_logic_vector(cnt+78,32) then

				wait_flag <= '1';	--Pulso para incremento de waits das tarefas no escalonador
			else
				wait_flag <= '0';
			end if;
			
			--Define o número da tarefa ativa como um vetor binário
			task_number <= to_stdlogicvector(to_bitvector((ZERO(31 downto 1) & '1')) SLL task_ativa);			
		end if;
	end process;

	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--PROCESSO AUXILIAR PARA EVITAR TROCAS DE TAREFAS INDESEJADAS OU DESNECESSÁRIAS
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process(clk, task_ativa, task_next, restore_init)
	begin
		if rising_edge(clk) then
			if task_ativa = conv_integer(unsigned(task_next)) then
				tick_enable <= '0';	--Desabilita a troca de taretas no próximo tick
			else
				tick_enable <= '1';	--Habilita
--				task_futura <= conv_integer(unsigned(task_next));	--17/05/17 melhora de sincronismo
--				task_antiga <= task_ativa; --17/05/17 troquei o ponto de atualização
			end if;
		end if;
			
	end process;
	
	--Separado em dois processos um para cada borda para compatibilizar com
	--o Encaounte (Cadence)	
	process(task_ativa, task_next, restore_init, tick_enable)
	begin
		--17/05/17 Melhora no sincronismo
		if rising_edge(restore_init) then
			if(tick_enable = '1') then
				task_futura <= conv_integer(unsigned(task_next));
			end if;
		end if;
			
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--SINAIS DA MÁQUINA DE ESTADOS MOTOR
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	input3 <= 					  sleep_yield & tick_enable   & restore_flag & 
				 restore_ready & tick_flag   & switch_out_RT & backup_ready;
	atualiza_task_ativa <= output3(4); --17/05/17
	restore_init 	<= output3(3);
	task_switch_RT <= output3(2);
	bank_switch 	<= output3(1);
	backup_init 	<= output3(0);

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--MÁQUINA DE ESTADOS MOTOR PARA TROCA DE TAREFAS (TASK_SWITCH) -> define o estado
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process(clk, reset, escalonador(0), input3)
	begin
		if reset = '1' or escalonador(0) = '0' then
			state_motor <= s0;
		elsif rising_edge(clk) then
			case state_motor is
				when s0=>
					if (input3(5) = '1') AND (input3(4) = '1') then	--tick_enable & restore_flag
						state_motor <= s1;
					elsif input3(6) = '1' then	--sleep_yield
						state_motor <= s6;
					else
						state_motor <= s0;
					end if;
				when s1=>
					if input3(3) = '1' then	--restore_ready
						state_motor <= s2;
					elsif input3(6) = '1' then	--sleep_yield
						state_motor <= s8;
					else
						state_motor <= s1;
					end if;
				when s2=>
					if (input3(2) = '1') OR (input3(6) = '1') then --tick_flag ou sleep_yield
						state_motor <= s3;
					else
						state_motor <= s2;
					end if;
				when s3=>
					if input3(1) = '1' then --switch_out_RT
						state_motor <= s4;
					else
						state_motor <= s3;
					end if;
				when s4=>
--					state_motor <= s5;
					if input3(1) = '0' then --/switch_out_RT (19/05/17)
						state_motor <= s5;
					else
						state_motor <= s4;
					end if;
				when s5=>
					if input3(0) = '1' then --backup_ready
						state_motor <= s0;
					elsif input3(6) = '1' then	--sleep_yield
						state_motor <= s9;
					else
						state_motor <= s5;
					end if;
				when s6=>
					if input3(5) = '1' then --tick_enable
						state_motor <= s7;
					else
						state_motor <= s6;
					end if;
				when s7=>
					if input3(3) = '1' then --restore_ready
						state_motor <= s3;
					else
						state_motor <= s7;
					end if;
				when s8=>
					if input3(3) = '1' then --restore_ready
						state_motor <= s3;
					else
						state_motor <= s8;
					end if;
				when s9=>
					if input3(0) = '1' then --backup_ready
						state_motor <= s6;
					else
						state_motor <= s9;
					end if;					
			end case;
		end if;
	end process;	

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--MÁQUINA DE ESTADOS MOTOR PARA TROCA DE TAREFAS (TASK_SWITCH) -> define o estado
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (state_motor)
	begin
		case state_motor is
			when s0 =>
				output3 <= "00000";	--nenhuma ação
				debug_state_motor <= "0000";
			when s1 =>
				output3 <= "01000";	--restore_init
				debug_state_motor <= "0001";
			when s2 =>
				output3 <= "00000";	--nenhuma ação
				debug_state_motor <= "0010";
			when s3 =>
				output3 <= "10100";	--task_switch_RT E aualiza_task_ativa
				debug_state_motor <= "0011";
			when s4 =>
				output3 <= "00010";	--bank_switch
				debug_state_motor <= "0100";
			when s5 =>
				output3 <= "00001";	--backup_init
				debug_state_motor <= "0101";
			when s6 =>
				output3 <= "00100";	--task_switch_RT
				debug_state_motor <= "0110";
			when s7 =>
				output3 <= "01100";	--restore_init E task_switch_RT
				debug_state_motor <= "0111";
			when s8 =>
				output3 <= "01100";	--task_switch_RT E restore_init
				debug_state_motor <= "1000";
			when s9 =>
				output3 <= "00101";	--task_switch_RT E backup_init
				debug_state_motor <= "1001";
		end case;
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	-->>>> FICA <<< TROCA DE BANCOS (BANK_SWITCH) -> define pc_backup (etapa 2)
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	troca_bancos: process(bank_switch, reset)
	begin
		if reset = '1' then
			sel_bank <= '0';
		
		elsif rising_edge(bank_switch) then
--			--Faz o backup do PC antigo
--			pc_backup <= pc_backup_RT & "00";  --<<<<<<<<<17/05/17 foi alterado para aceitar sleep, deve ocorrer quanto switch_out_RT vai para 1
			--Inverto o banco de registradores ativo
			if	sel_bank = '0' then
				sel_bank <= '1';
			else
				sel_bank <= '0';
			end if;
		end if;		
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	-->>>> NOVO 17/05/17 <<< DISPARA BACKUP DO PC
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
--	backup_pc: process (switch_out_RT, pc_backup_RT)
--	begin
--		--Assim que a CPU simaliza que encontrou um ponto de parada e parou
--		if rising_edge(switch_out_RT) then
--			--Faz o backup do PC
--			pc_backup <= pc_backup_RT & "00";
--		end if;
--		--Essa solução compatibiiza tanto as trocas de tarefas síncronas como assíncronas
--	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--SINAIS DA MÁQUINA DE ESTADOS PC_BACKUP
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	input4 <= backup_init & switch_out_RT;
		
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--MÁQUINA DE ESTADOS PC_BACKUP -> define o estado
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process(clk, reset, input4)
	begin
		if reset = '1' then
			state_pc_backup <= s0;
		elsif rising_edge(clk) then
			case state_pc_backup is
				when s0=>						--Aquarda novo backup em dois níveis
					if input4(0) = '1' then		--Quando CPU sinaliza que parou e atualizou pc_backup_RT
						state_pc_backup <= s1;
					else
						state_pc_backup <= s0;
					end if;
				when s1=>						--Backup de 1o nível (pc_backup_temp = pc_backup_RT)
					if input4 = "10" then		--Início do backup da tarefa pelo context_manager
						state_pc_backup <= s2;
					else
						state_pc_backup <= s1;
					end if;
--				when s2=>						--Backup de 2o nível (pc_backup = pc_backup_temp)
--					if input4(0) = '0' then		--Aguarda próxima sinalização de parada da CPU
--						state_pc_backup <= s0;
--					else								--Faz novo backup de 1o nível
--						state_pc_backup <= s1;
--					end if;
				when s2=>						--Backup de 2o nível (pc_backup = pc_backup_temp)
					if input4(1) = '0' then		--Reinicia e aquarda novo backup em dois níveis
						state_pc_backup <= s0;
					elsif input4 = "11" then			--Novo troca de tarefa antes de terminar o backup
						state_pc_backup <= s3;	--Faz novo backup de 1o nível
					else
						state_pc_backup <= s2;
					end if;
				when s3=>						--Backup de 1o nível (pc_backup_temp = pc_backup_RT)
					if input4(1) = '0' then		--Terminou o backup anterior
						state_pc_backup <= s4;
					else
						state_pc_backup <= s3;
					end if;
				when s4=>						--Aguarda próximo backup
					if input4 = "10" then		--Início do backup da tarefa pelo context_manager
						state_pc_backup <= s2;
					else
						state_pc_backup <= s4;
					end if;
					
			end case;
		end if;
	end process;

--	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
--	--SINAIS DA MÁQUINA DE ESTADOS PC_BACKUP
--	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
--	input4 <= backup_init & switch_out_RT;--bank_switch;
--		
--	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
--	--MÁQUINA DE ESTADOS PC_BACKUP -> define o estado
--	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
--	process(clk, reset, input4)
--	begin
--		if reset = '1' then
--			state_pc_backup <= s0;
--		elsif rising_edge(clk) then
--			case state_pc_backup is
--				when s0=>						--Aquarda novo backup em dois níveis
--					if input4(0) = '1' then		--Quando CPU sinaliza que parou e atualizou pc_backup_RT
--						state_pc_backup <= s1;
--					else
--						state_pc_backup <= s0;
--					end if;
--				when s1=>						--Backup de 1o nível (pc_backup_temp = pc_backup_RT)
--					if input4(1) = '1' then		--Início do backup da tarefa pelo context_manager
--						state_pc_backup <= s2;
--					else
--						state_pc_backup <= s1;
--					end if;
--				when s2=>						--Backup de 2o nível (pc_backup = pc_backup_temp)
--						state_pc_backup <= s0;
--				when s3=>						
--						state_pc_backup <= s0;			
--				when s4=>						
--						state_pc_backup <= s0;
--			
--						
--			end case;
--		end if;
--	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--MÁQUINA DE ESTADOS PC_BACKUP -> define a saída
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (state_pc_backup)
	begin
		case state_pc_backup is
			when s0 =>
				output4 <= "00";							--Nenhuma ação
				debug_state_pc_backup <= "000";
			when s1 =>
				output4 <= "01";							--Backup de 1o nível
				debug_state_pc_backup <= "001";
			when s2 =>
				output4 <= "10";							--Backup de 2o nível
				debug_state_pc_backup <= "010";
			when s3 =>
				output4 <= "01";							--Backup de 1o nível
				debug_state_pc_backup <= "011";
			when s4 =>
				output4 <= "00";							--Nenhuma ação
				debug_state_pc_backup <= "100";
		end case;
	end process;

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--DEFINE COMO OS BACKUPS SÃO FEITOS COM BASE NAS SAÍDAS
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (output4(0), pc_backup_RT)
	begin
		--Ao iniciar o escalonador todas as tarefas existentes sao colocadas em estado ready
		if rising_edge(output4(0)) then
			pc_backup_temp <= pc_backup_RT & "00";
		end if;
	
	end process;	
	
	--Separado em dois processos um para cada borda para compatibilizar com
	--o Encaounte (Cadence)	
	process (output4(1), pc_backup_temp)
	begin
		if	rising_edge(output4(1)) then
			pc_backup <= pc_backup_temp;
		end if;
		
	end process;	
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	-->>>> NOVO <<< HABILITA TROCA DE TAREFA COM BASE NA PRÓXIMA SUGERIDA PELO ESCALONADOR
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX	
	process(task_futura, task_ativa, reset, output3(2), atualiza_task_ativa) --foi removido task_switch_RT
	begin
		if reset = '1' then
			task_ativa <= 0;
		--elsif falling_edge(task_switch_RT) then
		--elsif falling_edge(output3(2)) then
		--elsif falling_edge(atualiza_task_ativa) then --17/05/17
		elsif rising_edge(atualiza_task_ativa) then --21/05/17
			--Funcionamento baseado nos backups restaurados (testei com disparo por restore_ready e não funcionou)
			--pc_RT <= pc_restore(31 downto 2);
			task_ativa <= task_futura;
			task_antiga <= task_ativa;	--17/05/17 assim apenas no momento da troca de tarefas é feita a atualização
		end if;		
	end process;
	--!!!!!!!!!!!!!!!!!!!!!Aualiza PC_restore assim que a restauração fica pronta
	--Funcionou!!!!!!!!!!!!!!!!!!!!!!!!!!!
	process(restore_ready) --foi removido task_switch_RT
	begin
--		if falling_edge(restore_ready) then
		if rising_edge(restore_ready) then	--(22/05/17 madrugada)
			--Funcionamento baseado nos backups restaurados (testei com disparo por restore_ready e não funcionou)
			pc_RT <= pc_restore(31 downto 2);			
		end if;		
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--SINAIS DA MÁQUINA DE ESTADOS
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--input2 <= (tick_flag and tick_enable) & escalonador(0); --Bloquei o fluxo pela máquina de estados
	--input2 <= tick_flag & escalonador(0);	--retirado 03/05/17
	input2 <= bank_switch & escalonador(0);	--implementado 03/05/17
		
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--MÁQUINA DE ESTADOS PARA TROCA DE ESTADO DAS TAREFAS (TASK_STATE) -> define o estado
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process(clk, reset, escalonador(0)) --faltou input2
	begin
		if reset = '1' or escalonador(0) = '0' then
			state_tarefas <= s0;
		elsif rising_edge(clk) then
			case state_tarefas is
				when s0=>
					if input2 = "01" then	--Ativa o funcionamento da máquina quando tick = 0 e escalondor = 1
						state_tarefas <= s1;
					else
						state_tarefas <= s0;
					end if;
				when s1=>
					if input2 = "11" then	--Atualiza estados das tarefas
						state_tarefas <= s2;
					elsif input2 = "01" then
						state_tarefas <= s1;
					else
						state_tarefas <= s0;
					end if;
				when s2=>
					if input2 = "01" then	--Aguarda nova troca de tarefas
						state_tarefas <= s3;
					elsif input2 = "11" then
						state_tarefas <= s2;
					else
						state_tarefas <= s0;
					end if;
				when s3=>
					if input2 = "11" then	--Atualiza estados das tarefas
						state_tarefas <= s2;
					elsif input2 = "01" then
						state_tarefas <= s3;
					else
						state_tarefas <= s0;
					end if;
			end case;
		end if;
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--MÁQUINA DE ESTADOS PARA TROCA DE ESTADO DAS TAREFAS (TASK_STATE) -> define a saída
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (state_tarefas)
	begin
		case state_tarefas is
			when s0 =>
				output2 <= "00";							--Nenhuma ação
				debug_state_tarefas <= "00";
			when s1 =>
				output2 <= "01";							--Tarefas ativas em estado ready
				debug_state_tarefas <= "01";
			when s2 =>
				output2 <= "10";							--Ativa = running, Antiga = ready
				debug_state_tarefas <= "10";
			when s3 =>
				output2 <= "11";							--Atualiza estados
				debug_state_tarefas <= "11";
		end case;
	end process;

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--DEFINE A CONDIÇÃO INICIAL DAS TAREFAS COM BASE NOS ESTADOS DA SAÍDA
	--Alterado 03/05/17 para considerar os contadores de sleep e o estado blocked
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (output2, clk, escalonador, task_live, task_ativa, task_antiga, task_state,task_live_old)
--		variable index : natural := 0;
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
				task_live_old <= task_live;
			elsif output2 = "10" then
				for index in 0 to 31 loop
					--Se a tarefa existe
					if task_live(index) = '1' then
						--Se é a tarefa futura
						if index = task_futura then
							task_state(task_futura) <= "11";	--Estado = running (rodando) "poderia ser task_ativa"	
						--Senão, se é a tarefa antiga
						elsif index = task_antiga then
							task_state(task_antiga) <= "10";	--Estado = ready (pronta)	
						else						
							task_state(index) <= task_state(index);	--Estado = mantém
						
--						else						
--							task_state(index) <= "10";		--Estado inicial = ready (pronta)
						end if;
					end if;		
				end loop;
			elsif output2 = "11" then
				--Alteração para uso de sleep e yield (03/05/17) !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				for index in 0 to 31 loop
					--Se a tarefa existe e antes não existia
					if task_live(index) = '1' and  task_live_old(index) = '0' then
						task_state(index) <= "10";		--Estado = ready (pronta)							
					--Senão, se a tarefa não existe e antes existia
					elsif task_live(index) = '0' and  task_live_old(index) = '1' then
						task_state(index) <= "00";		--Estado = suspend (suspensa)
					--Senão, se a tarefa existe mas está com seu contador de sleep != 0
					elsif task_live(index) = '1' and  counter_done(index) = '0' then
						task_state(index) <= "01";		--Estado = blocked (bloqueada)
					--Senão, se a tarefa existe mas está com seu contador de sleep = 0
					elsif task_live(index) = '1' and  counter_done(index) = '1' and index /= task_ativa then
						task_state(index) <= "10";		--Estado = ready (pronta)
					--Senão, mantém o valor anterior
					else
						task_state(index) <= task_state(index);	--Estado = mantém
					end if;
				end loop;
				--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				
				--Atualiza o registrador de valor antigo;
				task_live_old <= task_live;
			elsif output2 = "00" then
				for index in 0 to 31 loop
					task_state(index) <= "00";		--Estado inicial = suspend (suspensa)
				end loop;
				task_live_old <= task_live;
			end if;
		end if;
		--Não está sendo utilizada	
		if task_live /= task_live_old then
			live_flag <= '1';
		else
			live_flag <= '0';
		end if;
	end process;
	
	--Atualiza os estados de todas as tarefas (utilizado pelo escalonador)
	task_state7_0		<= task_state(7) & task_state(6) & task_state(5) & task_state(4) & 
								task_state(3) & task_state(2) & task_state(1) & task_state(0);
	task_state15_8		<= task_state(15) & task_state(14) & task_state(13) & task_state(12) & 
								task_state(11) & task_state(10) & task_state(9) & task_state(8);						
	task_state23_16	<= task_state(23) & task_state(22) & task_state(21) & task_state(20) & 
								task_state(19) & task_state(18) & task_state(17) & task_state(16);	
	task_state31_24	<= task_state(31) & task_state(30) & task_state(29) & task_state(28) & 
								task_state(27) & task_state(26) & task_state(25) & task_state(24);	

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--DEFINE SE ALGUMA TAREFA ENTRARÁ EM ESTADO SLEEP OU YIELD
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX								
	load_sleep_flag(1) <= task_sleep(16) when task_ativa = 1 else '0';
	load_sleep_flag(2) <= task_sleep(16) when task_ativa = 2 else '0';
	load_sleep_flag(3) <= task_sleep(16) when task_ativa = 3 else '0';
	load_sleep_flag(4) <= task_sleep(16) when task_ativa = 4 else '0';
	load_sleep_flag(5) <= task_sleep(16) when task_ativa = 5 else '0';
	load_sleep_flag(6) <= task_sleep(16) when task_ativa = 6 else '0';
	load_sleep_flag(7) <= task_sleep(16) when task_ativa = 7 else '0';
	load_sleep_flag(8) <= task_sleep(16) when task_ativa = 8 else '0';
--	load_sleep_flag(8 downto 1) <= "00000000";
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--CONTROLA O PEDIDO DE TROCA DE TAREFA POR SLEEP OU YIELD (sleep_yield)
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX								
	timers: process (clk, reset_in, task_ativa)
	begin
		--Se for reset zera as cargas
		if reset_in = '1' then
			sleep_yield <= '0';
		--Se a tarefa ativa for a 1
		elsif rising_edge(clk) then
			case task_ativa is
				when 0 => sleep_yield <= '0';	--Tarefa 0 (idle) não aceita sleep ou yield
				when 1 => sleep_yield <= not counter_done(1);
				when 2 => sleep_yield <= not counter_done(2);
				when 3 => sleep_yield <= not counter_done(3);
				when 4 => sleep_yield <= not counter_done(4);
				when 5 => sleep_yield <= not counter_done(5);
				when 6 => sleep_yield <= not counter_done(6);
				when 7 => sleep_yield <= not counter_done(7);
				when 8 => sleep_yield <= not counter_done(8);
				when others => sleep_yield <= '0';
			end case;
		end if;
	end process;	

end; --architecture logic
