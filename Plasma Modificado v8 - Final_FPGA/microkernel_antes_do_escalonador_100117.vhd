---------------------------------------------------------------------
-- TITLE: Microkernel
-- AUTHOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATE CREATED: 2/11/16
-- FILENAME: microkernel.vhd
-- PROJECT: Plasma CPU Modificado v2
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
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_ARITH.ALL;

entity microkernel is
	port(	clk          			: in std_logic;
			reset_in     			: in std_logic;
			counter		 			: in std_logic_vector(31 downto 0);			--x Entrada de contador para definição da troca de tarefas (substituido pelo sinal de clock)
			
			--Configuração e uso do escalonador
			escalonador  			: in std_logic_vector(0 downto 0);			--Bit 0 habilita o escalonador
			tick			 			: in std_logic_vector(31 downto 0);			--Tempo do tick em pulsos de clock
			task_mumber	 			: in std_logic_vector(31 downto 0);			--Quantidade de tarefas
			task_live	 			: in std_logic_vector(31 downto 0);			--Vetor de tarefas (existe/não existe, máx. 32)

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
	-- Build an enumerated type for the state machine
	type state_type is (s0, s1, s2, s3);

	-- Register to hold the current state
	signal state   : state_type;	
	
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
	--Código
	sel_bank_RT 			<= sel_bank;	--0/1 inverte o banco utilizado pela CPU
	
	--Microkernel conectado as fontes de pause da CPU
	--pause_RT					<= open;
			
	--Microkernel conectado ao bloco mem_ctrl
	--mem_source_RT			<= open;
	
	--Saída para depuração (criado em 24/11/16)
	mk_debug					<= ZERO(7 downto 6) & switch_out_RT & restore_ready & restore_flag & tick_flag & escalonador(0) & sel_bank;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--SINAIS DA MÁQUINA DE ESTADOS
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	input <= tick_flag & switch_out_RT;
	task_switch_RT <= output(0);
	bank_switch <= output(1);
	context_backup <= output(2);
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--SINALIZAÇÃO DE FIM DE TIME SLICE (DISPARA MÁQUINA DE ESTADOS) -> tick_flag e restore_flag
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process(clk, reset, escalonador(0), tick)
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
		
		end if;
	end process;

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--MÁQUINA DE ESTADOS PARA TROCA DE TAREFAS (TASK_SWITCH) -> define o estado
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process(clk, reset, escalonador(0))
	begin
		if reset = '1' or escalonador(0) = '0' then
			state <= s0;
		elsif rising_edge(clk) then
			case state is
				when s0=>
					if input(1) = '1' then	--Ativa o funcionamento da máquina quando tick_flag = 1
						state <= s1;
					else
						state <= s0;
					end if;
				when s1=>
					if input(0) = '1' then	--Entra em atendimento da solicitação
						state <= s2;
					else
						state <= s1;
					end if;
				when s2=>
						state <= s3;
				when s3=>
						state <= s0;
			end case;
		end if;
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--MÁQUINA DE ESTADOS PARA TROCA DE TAREFAS (TASK_SWITCH) -> define a saída
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (state)
	begin

		case state is
			when s0 =>
				output <= "000";							--Troca de contexto desativada
			when s1 =>
				output <= "001";							--Ativa troca de tarefa (etapa 1)
			when s2 =>
				output <= "010";							--Ativa troca de bancos (etapa 2)
			when s3 =>
				output <= "100";							--Ativa troca de contexto (etapa 3)
		end case;
	end process;

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--TROCA DE BANCOS (BANK_SWITCH) -> define pc_backup (etapa 2)
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process(bank_switch, reset)
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
	--DISPARA BACKUP DE CONTEXTO (CONTEXT_SWITCH) -> backup_init
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (context_backup, reset, backup_ready)
	begin
		-- Reseta devido ao sinal de reset ou confiramação de conclusão do backup
		if reset = '1' or backup_ready = '1' then
			backup_init <= '0';
		-- Dispara pedido de backup através do sinal context_backup (vide máquina de estados)
		elsif (rising_edge(context_backup)) then
			backup_init <= '1';
		end if;
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--DISPARA RESTAURAÇÃO DE CONTEXTO (CONTEXT_SWITCH)
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	process (restore_flag, reset, restore_ready, pc_restore)
	begin
		-- Reseta devido ao sinal de reset ou confiramação de conclusão da restauração
		if reset = '1' or restore_ready = '1' then
			restore_init <= '0';
		-- Dispara pedido de backup através do sinal context_backup (vide máquina de estados)
		elsif (rising_edge(restore_flag)) then
			restore_init <= '1';
		end if;
	end process;

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--DEFINE QUAL TAREFA SERÁ A PRÓXIMA E QUAL SOFRERÁ O BACKUP
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX	
	--Esse processo ainda é apenas para teste com tarefas fixas
	process(restore_flag, tick_flag, task_ativa) --No lugar de tick_flag poderia ser context_backup
	begin
		--Se ocorreu um pedido de restauração de tarefa
		if rising_edge(restore_flag) then
			--Se a tarefa em execução é a 0 então a futura = 1, a antiga = 0 e vice-versa
			if task_ativa = 0 or task_ativa = 10 then
				task_futura <= 1;
				task_antiga <= 0;
			elsif task_ativa = 1 or task_ativa = 11 then	--Teste 3 tarefas 14/12/16 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				task_futura <= 2;
				task_antiga <= 1;	
			elsif task_ativa = 2 or task_ativa = 12 then	--Teste 5 tarefas 16/12/16 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				task_futura <= 3;
				task_antiga <= 2;	
			elsif task_ativa = 3 or task_ativa = 13 then	--Teste 5 tarefas 16/12/16 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				task_futura <= 4;
				task_antiga <= 3;			
			elsif task_ativa = 4 then
				task_futura <= 0;
				task_antiga <= 4;		--Teste 3 tarefas 14/12/16 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			end if;				
		end if;
	end process;
		
--**	
	--ESSA PARTE VAI SER SUBSTITUIDA PELO TRATAMENTO DE RESTUARAÇÃO DE TAREFA
	--Assim que o contador atinge o valor para troca de tarefas, carrega a saída com o PC da próxima tarefa
	process(tick_flag, task_ativa, reset)
	begin
		if reset = '1' then
			task_ativa <= 0;
		elsif rising_edge(tick_flag) then
			--Funcionamento baseado nos backups restaurados (testei com disparo por restore_ready e não funcionou)
			pc_RT <= pc_restore(31 downto 2);
			
			if task_ativa = 0 then
--				pc_RT <= zero(31 downto 9) & "0100111";	--09C Ativa troca de tarefa com endereço da tarefa 2 Plasma_RT6
				task_ativa <= 1;
			elsif task_ativa = 1 then
--				pc_RT <= zero(31 downto 9) & "0111001";	--0E4 Ativa troca de tarefa com endereço da tarefa 3 Plasma_RT6
				task_ativa <= 2;
			elsif task_ativa = 2 then
--				pc_RT <= zero(31 downto 9) & "1001011";	--12C Ativa troca de tarefa com endereço da tarefa 5 Plasma_RT6
				task_ativa <= 3;
			elsif task_ativa = 3 then
--				pc_RT <= zero(31 downto 9) & "1011101";	--174 Ativa troca de tarefa com endereço da tarefa 5 Plasma_RT6
				task_ativa <= 4;
			elsif task_ativa = 4 then
--				pc_RT <= zero(31 downto 9) & "0011011";	--06C Ativa troca de tarefa com endereço da tarefa 1 Plasma_RT6
--				task_ativa <= 10;
				task_ativa <= 0;
--			elsif task_ativa = 10 then
--				pc_RT <= zero(31 downto 9) & "0101101";	--0B4 Ativa troca de tarefa com endereço da tarefa 5 Plasma_RT6
--				task_ativa <= 11;
--			elsif task_ativa = 11 then
--				pc_RT <= zero(31 downto 9) & "0111111";	--0FC Ativa troca de tarefa com endereço da tarefa 5 Plasma_RT6
--				task_ativa <= 12;
--			elsif task_ativa = 12 then
--				pc_RT <= zero(31 downto 9) & "1010001";	--144 Ativa troca de tarefa com endereço da tarefa 5 Plasma_RT6
--				task_ativa <= 13;
--			elsif task_ativa = 13 then
--				pc_RT <= zero(31 downto 9) & "1011101";	--174 Ativa troca de tarefa com endereço da tarefa 5 Plasma_RT6
--				task_ativa <= 4;
			end if;
		end if;
	end process;

end; --architecture logic
