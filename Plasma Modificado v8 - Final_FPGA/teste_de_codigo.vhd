--Estrutura de teste
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;
--use ieee.numeric_std.all;
use IEEE.STD_LOGIC_ARITH.ALL;

entity teste_de_codigo is
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
			mk_debug					: out std_logic_vector(7 downto 0));
		
end; --entity microkernel

architecture logic of teste_de_codigo is
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
	
	-- Build an enumerated type for the state machine
	type state_type is (s0, s1, s2, s3);
	-- Register to hold the current state
	signal state   : state_type;
	
	-- Build an enumerated type for the state machine
	type state_type3 is (s0, s1, s2, s3, s4, s5, s6, s7, s8, s9);
	-- Register to hold the current state
	signal state_motor   : state_type3;
	
	signal input3			: std_logic_vector(6 downto 0);
	signal output3			: std_logic_vector(3 downto 0);

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
		
		--Configuração e uso do escalonador
		task_live,
		
		--Informações para uso do algoritmo
		--Priodidade (3 bits): níveis de 0 a 7 (o é a maior prioridade)
		task_pri7_0,
		task_pri15_8,
		task_pri23_16,
		task_pri31_24,
		--Estados (2 bits): 0-Suspensa, 1-Bloqueada, 2-Pronta, 3-Rodando
		task_state7_0,
		task_state15_8,
		task_state23_16,
		task_state31_24,
		
		--Próxima tarefa
		task_next
	);
	
	u4_counter_down_1: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(1)),
      load		=> load_sleep_flag(1),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(0)
      --cnt_out		--para teste
	);
	
	u5_counter_down_2: counter_down
	port map(	
		clk		=>	tick_flag, --tick do escalonador --talvez usar wait_flag, assim quando ocorrer o restore_flag a tarefa blocked por yield entraria na análise
		reset		=> not(task_live(2)),
      load		=> load_sleep_flag(2),
      sleep 	=> task_sleep(15 downto 0),
		done		=> counter_done(1)
      --cnt_out		--para teste
	);
	
	--Por enquanto apenas um contador ativo
	counter_done(31 downto 2) <= ones(31 downto 2);
	
	--Código
	sel_bank_RT 			<= sel_bank;	--0/1 inverte o banco utilizado pela CPU
	
	--Microkernel conectado as fontes de pause da CPU
	--pause_RT					<= open;
			
	--Microkernel conectado ao bloco mem_ctrl
	--mem_source_RT			<= open;
	
	--Saída para depuração (criado em 24/11/16)
	mk_debug					<= output2 & switch_out_RT & restore_ready & restore_flag & tick_flag & escalonador(0) & sel_bank;
	
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
			if tick = conv_std_logic_vector(cnt+68,32) then
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
		
		end if;
	end process;

	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--PROCESSO AUXILIAR PARA EVITAR TROCAS DE TAREFAS INDESEJADAS OU DESNECESSÁRIAS
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process(clk, task_ativa, task_next)
	begin
		if rising_edge(clk) then
			if task_ativa = conv_integer(unsigned(task_next)) then
				tick_enable <= '0';	--Desabilita a troca de taretas no próximo tick
			else
				tick_enable <= '1';	--Habilita
				task_futura <= conv_integer(unsigned(task_next));
				task_antiga <= task_ativa;
			end if;
		end if;		
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--SINAIS DA MÁQUINA DE ESTADOS MOTOR
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	input3 <= 					  sleep_yield & tick_enable   & restore_flag & 
				 restore_ready & tick_flag   & switch_out_RT & backup_ready;
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
					state_motor <= s5;
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
					if input3(3) = '1' then --backup_ready
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
				output3 <= "0000";	--nenhuma ação
			when s1 =>
				output3 <= "1000";	--restore_init
			when s2 =>
				output3 <= "0000";	--nenhuma ação
			when s3 =>
				output3 <= "0100";	--task_switch_RT
			when s4 =>
				output3 <= "0010";	--bank_switch
			when s5 =>
				output3 <= "0001";	--backup_init
			when s6 =>
				output3 <= "0100";	--task_switch_RT
			when s7 =>
				output3 <= "1100";	--restore_init E task_switch_RT
			when s8 =>
				output3 <= "0100";	--task_switch_RT
			when s9 =>
				output3 <= "0100";	--task_switch_RT
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
			--Faz o backup do PC antigo
			pc_backup <= pc_backup_RT & "00";
			--Inverto o banco de registradores ativo
			if	sel_bank = '0' then
				sel_bank <= '1';
			else
				sel_bank <= '0';
			end if;
		end if;		
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	-->>>> NOVO <<< HABILITA TROCA DE TAREFA COM BASE NA PRÓXIMA SUGERIDA PELO ESCALONADOR
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX	
	process(task_futura, task_ativa, reset, output3(2)) --foi removido task_switch_RT
	begin
		if reset = '1' then
			task_ativa <= 0;
		--elsif falling_edge(task_switch_RT) then
		elsif falling_edge(output3(2)) then
			--Funcionamento baseado nos backups restaurados (testei com disparo por restore_ready e não funcionou)
			pc_RT <= pc_restore(31 downto 2);
			task_ativa <= task_futura;
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
			when s1 =>
				output2 <= "01";							--Tarefas ativas em estado ready
			when s2 =>
				output2 <= "10";							--Ativa = running, Antiga = ready
			when s3 =>
				output2 <= "11";							--Nenhuma ação
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
							task_state(task_futura) <= "11";	--Estado = running (rodando)	
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
				--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				--Substituir o "for" anterior, usar bank_switch no lugar do tick_flag
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

	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--CONTROLA O PEDIDO DE TROCA DE TAREFA POR SLEEP OU YIELD (sleep_yield)
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX								
	timers: process (clk, reset_in, task_ativa)
	begin
		--Se for reset zera as cargas
		if reset_in = '1' then
			sleep_yield <= '0';
		--Senão
		elsif rising_edge(clk) then
			case task_ativa is
				when 0 => sleep_yield <= '0';	--Tarefa 0 (idle) não aceita sleep ou yield
				when 1 => sleep_yield <= counter_done(1);
				when 2 => sleep_yield <= counter_done(2);
				when 3 => sleep_yield <= counter_done(3);
				when 4 => sleep_yield <= counter_done(4);
				when 5 => sleep_yield <= counter_done(5);
				when 6 => sleep_yield <= counter_done(6);
				when 7 => sleep_yield <= counter_done(7);
				when 8 => sleep_yield <= counter_done(8);
				when others => sleep_yield <= '0';
			end case;
		end if;
	end process;	

end; --architecture logic
