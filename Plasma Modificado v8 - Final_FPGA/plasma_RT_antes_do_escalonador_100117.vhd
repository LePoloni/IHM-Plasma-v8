---------------------------------------------------------------------
-- TITLE: Plasma (CPU core with memory)
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 6/4/02
-- FILENAME: plasma.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    This entity combines the CPU core with memory and a UART.
--
-- Memory Map (original):
--   0x00000000 - 0x0000ffff   Internal RAM (8KB)
--   0x10000000 - 0x100fffff   External RAM (1MB)
--   Access all Misc registers with 32-bit accesses
--   0x20000000  Uart Write (will pause CPU if busy)
--   0x20000000  Uart Read
--   0x20000010  IRQ Mask
--   0x20000020  IRQ Status
--   0x20000030  GPIO0 Out Set bits
--   0x20000040  GPIO0 Out Clear bits
--   0x20000050  GPIOA In
--   0x20000060  Counter
--   0x20000070  Ethernet transmit count
--   IRQ bits:
--      7   GPIO31
--      6  ^GPIO31
--      5   EthernetSendDone
--      4   EthernetReceive
--      3   Counter(18)
--      2  ^Counter(18)
--      1  ^UartWriteBusy
--      0   UartDataAvailable

-- Memory Map (modificado):
--   0x00000000 - 0x0000ffff   Internal RAM ou ROM (8KB) --> Programa a ser executado
--   0x00010000 - 0x0001ffff   Internal RAM (8KB) --> Uso geral, alocação de tarefas e variáveis
--   0x00020000 - 0x0002ffff   Internal RAM (8KB) --> Alocação das TCBs das tarefas
--   0x10000000 - 0x100fffff   External RAM (1MB)
--   Access all Misc (abreviação miscellaneous) registers with 32-bit accesses
--   0x20000000  Uart Write (will pause CPU if busy)
--   0x20000000  Uart Read
--   0x20000010  IRQ Mask
--   0x20000020  IRQ Status
--   0x20000030  GPIO0 Out Set bits
--   0x20000040  GPIO0 Out Clear bits
--   0x20000050  GPIOA In
--   0x20000060  Counter
--   0x20000070  Ethernet transmit count
--   0x20000080  Habilita o escalonador
--   0x20000090  Tempo do tick em pulsos de clock
--   0x200000A0  Quantidade de tarefas
--   0x200000B0  Vetor de tarefas (existe/não existe, máx. 32)
--   IRQ bits:
--      7   GPIO31
--      6  ^GPIO31
--      5   EthernetSendDone
--      4   EthernetReceive
--      3   Counter(18)
--      2  ^Counter(18)
--      1  ^UartWriteBusy
--      0   UartDataAvailable

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 16/7/16
-- MODIFICADO: 2/11/16
-- Substituidos os blocos alu, mult e shifter pelo bloco alu_mult_shifter (presente em *)
-- Substituido trechos do código pelo bloco reset_controller (presente em *)
-- Substituido o bloco pc_next pelo bloco pc_next_RT (presente em * e **)
-- Substituido o bloco reg_bank pelo bloco reg_bank_duplo_RT (presente em * e **)
-- Susbstituido o bloco mlite_cpu_mod (*) pelo bloco mlite_cpu_RT (**)
-- Alateração para 3 RAMs e registradores do microkernel
-- Criado o bloco microkernel (ainda vazio) para operação em real-time
-- MODIFICADO: 10/11/16
-- Criado conjunto de pinos para depuração
-- 24/11/16 - Incluido o sinal mk_debug no Microkernel
-- 28/11/16 - Ajuste na lista de sensibilidade do processo misc_proc:
--		  		  ram_data_r_dt, ram_data_r_rt, escalonador_rt_reg,
--				  tick_rt_reg, task_mumber_rt_reg, task_live_rt_reg
--				- Ajuste na lista de sensibilidade do processo ram_proc:
--				  escalonador_rt_reg
-- 			- Eliminado a conexão mem_source_RT	=> mem_source_RT entre
--				  mlite_cpu_RT e microkernel
--				- Criação de valor para ram_enable_dt <= '0'; e ram_enable_rt <= '0';
--				  em processo
--				- Alterado a posição de atualização das memórias no processo ram_proc para fora do if:
--					ram_byte_we <= byte_we_next;
--					ram_byte_we_dt <= byte_we_next;
--					ram_address(31 downto 2) <= address_next(31 downto 2);
--					ram_address_dt(31 downto 2) <= address_next(31 downto 2);
--					ram_data_w <= cpu_data_w;
--					ram_data_w_dt <= cpu_data_w;
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;

entity plasma_RT is
   --generic(memory_type : string := "XILINX_16X"; --"DUAL_PORT_" "ALTERA_LPM";	--LEANDRO: Comentado
	--generic(memory_type : string := "DUAL_PORT_";	--LEANDRO: Criado
	generic(memory_type : string := "ALTERA_LPM";	--LEANDRO: Criado para testar inversão dos arquivos com código fonte (2/11/16)
	        log_file    : string := "UNUSED";			--colocar nome do arquivo para gerar um log
           ethernet    : std_logic := '0';			--1 para criar uma porta ethernet
           use_cache   : std_logic := '0');			--1 para criar um cache
   port(clk          : in std_logic;
        reset        : in std_logic;

        uart_write   : out std_logic;
        uart_read    : in std_logic;

        address      : out std_logic_vector(31 downto 2);	--Sem ethernet fica igual ao sinal CPU_address
        byte_we      : out std_logic_vector(3 downto 0); 
        data_write   : out std_logic_vector(31 downto 0);
        data_read    : in std_logic_vector(31 downto 0);
        mem_pause_in : in std_logic;
        no_ddr_start : out std_logic;
        no_ddr_stop  : out std_logic;
        
        gpio0_out    : out std_logic_vector(31 downto 0);
        gpioA_in     : in std_logic_vector(31 downto 0);
		  
		  --Sinais para depuaração (10/11/16)
		  address_next_debug 	: out std_logic_vector(31 downto 2);
		  data_r_debug				: out	std_logic_vector(31 downto 0);  
		  ram_data_r_debug		: out	std_logic_vector(31 downto 0);
		  task_switch_RT_debug	: out std_logic; 
		  mk_debug					: out std_logic_vector(7 downto 0)
		  );
end; --entity plasma_RT

architecture logic of plasma_RT is
   signal address_next      : std_logic_vector(31 downto 2);
   signal byte_we_next      : std_logic_vector(3 downto 0);
   signal cpu_address       : std_logic_vector(31 downto 0);
   signal cpu_byte_we       : std_logic_vector(3 downto 0);
   signal cpu_data_w        : std_logic_vector(31 downto 0);
   signal cpu_data_r        : std_logic_vector(31 downto 0);
   signal cpu_pause         : std_logic;

   signal data_read_uart    : std_logic_vector(7 downto 0);
   signal write_enable      : std_logic;
   signal eth_pause_in      : std_logic;
   signal eth_pause         : std_logic;
   signal mem_busy          : std_logic;

   signal enable_misc       : std_logic;
   signal enable_uart       : std_logic;
   signal enable_uart_read  : std_logic;
   signal enable_uart_write : std_logic;
   signal enable_eth        : std_logic;

   signal gpio0_reg         : std_logic_vector(31 downto 0);
   signal uart_write_busy   : std_logic;
   signal uart_data_avail   : std_logic;
   signal irq_mask_reg      : std_logic_vector(7 downto 0);
   signal irq_status        : std_logic_vector(7 downto 0);		--Vetor de status de interrupções
   signal irq               : std_logic;
   signal irq_eth_rec       : std_logic;
   signal irq_eth_send      : std_logic;
   signal counter_reg       : std_logic_vector(31 downto 0);
	
	--RAM ou ROM interna para programa
   signal ram_enable        : std_logic;
   signal ram_byte_we       : std_logic_vector(3 downto 0);
   signal ram_address       : std_logic_vector(31 downto 2);
   signal ram_data_w        : std_logic_vector(31 downto 0);
   signal ram_data_r        : std_logic_vector(31 downto 0);	--Dado da RAM ou ROM interna para programa

   signal cache_access      : std_logic;
   signal cache_checking    : std_logic;
   signal cache_miss        : std_logic;
   signal cache_hit         : std_logic;
	
	--RAM interna para dados
	signal ram_enable_dt     : std_logic;
   signal ram_byte_we_dt    : std_logic_vector(3 downto 0);
   signal ram_address_dt    : std_logic_vector(31 downto 2);
   signal ram_data_w_dt     : std_logic_vector(31 downto 0);
   signal ram_data_r_dt     : std_logic_vector(31 downto 0);	--Dado da RAM interna para dados
	
	--RAM ou ROM interna para TCBs
	signal ram_enable_rt     : std_logic;
   signal ram_byte_we_rt    : std_logic_vector(3 downto 0);
   signal ram_address_rt    : std_logic_vector(31 downto 2);
   signal ram_data_w_rt     : std_logic_vector(31 downto 0);
   signal ram_data_r_rt     : std_logic_vector(31 downto 0);	--Dado da RAM interna para TCBs
	
	--Registadores para configuração e uso do escalonador
	signal escalonador_rt_reg   : std_logic_vector(31 downto 0);	--Bit 0 habilita o escalonador
	signal tick_rt_reg			 : std_logic_vector(31 downto 0);	--Tempo do tick em pulsos de clock
	signal task_mumber_rt_reg	 : std_logic_vector(31 downto 0);	--Quantidade de tarefas
	signal task_live_rt_reg		 : std_logic_vector(31 downto 0);	--Vetor de tarefas (existe/não existe, máx. 32)
	
	--Microkernel conectado ao bloco pc_next_RT
	signal pc_RT  					 : std_logic_vector(31 downto 2);	--30 bits para jump desvio de tarefa
	signal task_switch_RT 		 : std_logic;								--Força a troca de tarefa
	signal pc_backup_RT			 : std_logic_vector(31 downto 2);	--30 bits com o endereço da próxima instrução sem considerar troca de tarefa	
  
	--Microkernel conectado ao bloco reg_bank_duplo_RT
	signal rs_index_RT       	: std_logic_vector(5 downto 0);		--End. fonte de dados (6 bits ao invés de 5)
	signal rt_index_RT       	: std_logic_vector(5 downto 0);		--End. fonte de ou destino de dados
	signal rd_index_RT       	: std_logic_vector(5 downto 0);		--End. destino de dados
	signal reg_source_out_RT 	: std_logic_vector(31 downto 0);		--Saída de dados de acordo com rs
	signal reg_target_out_RT 	: std_logic_vector(31 downto 0);		--Saída de dados de acordo com rt
	signal reg_dest_new_RT   	: std_logic_vector(31 downto 0);		--Entrada de dados de acordo com rd
	signal intr_enable_RT    	: std_logic;								--Flag de enable de interrupção
  
	signal sel_bank_RT			: std_logic;								--Seleciona o banco utilizado pela CPU

	--Microkernel conectado as fontes de pause da CPU
	signal pause_RT				: std_logic;								--Sinaliza que a CPU está pausada, não trocar tarefa nesta hora	
	
	--Microkernel conectado ao bloco control
	signal switch_out_RT			: std_logic;								--Sinaliza pedido de switch em atendimento
	 
	--Sinais proveniente do Microkernel (podem ser desnecessários no futuro)
	signal mk_address       : std_logic_vector(31 downto 0);			--Microkernel - endereço da memória RAM TCB
   signal mk_byte_we       : std_logic_vector(3 downto 0);			--Microkernel - bytes para escrita na memória RAM TCB
   signal mk_data_w        : std_logic_vector(31 downto 0);			--Microkernel - dado para escrita na RAM TCB
   signal mk_data_r        : std_logic_vector(31 downto 0);			--Microkernel - dado para leitura na RAM TCB

	signal debug_cpu			: std_logic_vector(31 downto 2);			--Debug genérico para CPU
begin  --architecture
	--Habilita escrita em memória quando existe algum byte para escrita sinalizado (memória externa)
   write_enable <= '1' when cpu_byte_we /= "0000" else '0';
   --Memória ocupada quando solicitado pela porta ethernet ou pela memória externa
	mem_busy <= eth_pause or mem_pause_in;
	--Cache não utilizada
   cache_hit <= cache_checking and not cache_miss;
   --Pause na CPU
	cpu_pause <= (uart_write_busy and enable_uart and write_enable) or  --UART busy
      cache_miss or                                                    --Cache wait
      (cpu_address(28) and not cache_hit and mem_busy);                --DDR or flash
   --Vetor de status de interrupções formado pelas flags a seguir
	irq_status <= gpioA_in(31) & not gpioA_in(31) &
                 irq_eth_send & irq_eth_rec & 
                 counter_reg(18) & not counter_reg(18) &
                 not uart_write_busy & uart_data_avail;
   --Flag de interrupção depende da máscara criada para as possíveis fontes de interrupção
	irq <= '1' when (irq_status and irq_mask_reg) /= ZERO(7 downto 0) else '0';
   --Atualiza bits do port de saída com exceção dos bits 28~24.
	--Esses bits são mantidos zerados quando não usamos Ethernet (vide linhas 355~395)
	gpio0_out(31 downto 29) <= gpio0_reg(31 downto 29);
   gpio0_out(23 downto 0) <= gpio0_reg(23 downto 0);

	--Habilita acesso ao resgistradores mascarados (periféricos) quando o endereço estiver na
	--faixa estabelecida no mampeamento de memória (vide comentários no começo do arquivo)
   enable_misc <= '1' when cpu_address(30 downto 28) = "010" else '0';
	--Habilita a UART quando os periféricos estão habilitados e o endereço é o da UART
   enable_uart <= '1' when enable_misc = '1' and cpu_address(7 downto 4) = "0000" else '0';
   --Habilita leitura da UART se ela está habilitada e a escrita na memória não
	enable_uart_read <= enable_uart and not write_enable;
	--Habilita escrita da UART se ela está habilitada e a escrita na memória também
   enable_uart_write <= enable_uart and write_enable;
   --Habilita a Ethernet quando os periféricos estão habilitados e o endereço é o da Ethernet
	enable_eth <= '1' when enable_misc = '1' and cpu_address(7 downto 4) = "0111" else '0';
   --Força sempre os dois lsbs da CPU para 0, cada instrução consome 32 bits (pula de 4 em 4)
	cpu_address(1 downto 0) <= "00";
	
	--Sinais para depuaração (10/11/16)
--	address_next_debug 	<= address_next;
	data_r_debug			<= cpu_data_r;
	ram_data_r_debug		<= ram_data_r;
	task_switch_RT_debug	<= task_switch_RT;
	address_next_debug	<= debug_cpu;	--Teste 27/12/16 valor do pc_current
	
	--ESTA OPÇÃO DE CPU HABILITA AS ALTERAÇÕES PARA REAL-TIME		
	u1_cpu_RT: mlite_cpu_RT
      generic map (memory_type => memory_type)
      PORT MAP (
			clk          => clk,
         reset_in     => reset,
         intr_in      => irq,
 
         address_next => address_next,             --before rising_edge(clk)
         byte_we_next => byte_we_next,

         address      => cpu_address(31 downto 2), --after rising_edge(clk)
         byte_we      => cpu_byte_we,
         data_w       => cpu_data_w,
         data_r       => cpu_data_r,
         mem_pause    => cpu_pause,
			
			--Microkernel conectado ao bloco pc_next_RT
		   pc_RT  					=>	pc_RT,					--30 bits para jump desvio de tarefa
		   task_switch_RT 		=>	task_switch_RT,		--Força a troca de tarefa
			pc_backup_RT			=> pc_backup_RT,			--30 bits com o endereço da próxima instrução sem considerar troca de tarefa
			escalonador_RT			=> escalonador_rt_reg(0),--Sinalização do estado do escalonador
		  			
			--Microkernel conectado ao bloco reg_bank_duplo_RT
			rs_index_RT       	=> rs_index_RT,
			rt_index_RT       	=> rt_index_RT,
			rd_index_RT       	=> rd_index_RT,
			reg_source_out_RT 	=> reg_source_out_RT,
			reg_target_out_RT 	=> reg_target_out_RT,
			reg_dest_new_RT   	=> reg_dest_new_RT,
			intr_enable_RT    	=> intr_enable_RT,
		  
			sel_bank_RT				=> sel_bank_RT,				--0/1 inverte o banco utilizado pela CPU
			
			--Microkernel conectado as fontes de pause da CPU
			pause_RT					=> pause_RT,
			
		   --Microkernel conectado ao bloco control
		   switch_out_RT			=> switch_out_RT,								--Sinaliza pedido de switch em atendimento
			
			--Debug genérico da CPU
			debug_cpu				=> debug_cpu);

	--Neste projeto não estou usando a memória cache (por enquanto!?)
   opt_cache: if use_cache = '0' generate
      cache_access <= '0';
      cache_checking <= '0';
      cache_miss <= '0';
   end generate;
   
   opt_cache2: if use_cache = '1' generate
   --Control 4KB unified cache that uses the upper 4KB of the 8KB
   --internal RAM.  Only lowest 2MB of DDR is cached.
   u_cache: cache 
      generic map (memory_type => memory_type)
      PORT MAP (
         clk            => clk,
         reset          => reset,
         address_next   => address_next,
         byte_we_next   => byte_we_next,
         cpu_address    => cpu_address(31 downto 2),
         mem_busy       => mem_busy,

         cache_access   => cache_access,    --access 4KB cache
         cache_checking => cache_checking,  --checking if cache hit
         cache_miss     => cache_miss);     --cache miss
   end generate; --opt_cache2

	--Condições para memória ddr (externa)
   no_ddr_start <= not eth_pause and cache_checking;
   no_ddr_stop <= not eth_pause and cache_miss;
   --Condições para para a Ethernet
	eth_pause_in <= mem_pause_in or (not eth_pause and cache_miss and not cache_checking);

	--Processo sensível a muitos sinais relacionados ao acesso ao memória e periféricos
   misc_proc: process(clk, reset, cpu_address, enable_misc,
      ram_data_r, data_read, data_read_uart, cpu_pause,
      irq_mask_reg, irq_status, gpio0_reg, write_enable,
      cache_checking,
      gpioA_in, counter_reg, cpu_data_w, 
		ram_data_r_dt, ram_data_r_rt, escalonador_rt_reg,	--!!! Ajuste na lista de sensibilidade 28/12/16
		tick_rt_reg, task_mumber_rt_reg, task_live_rt_reg) --!!! Ajuste na lista de sensibilidade 28/12/16
   begin
		case cpu_address(30 downto 28) is
      
		--Acesso a RAM interna
--		when "000" =>         --internal RAM
--         cpu_data_r <= ram_data_r;
		
		--Acesso a RAM interna <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
		when "000" =>         --internal RAM/ROM
         if cpu_address(17 downto 16) = "00" then		--RAM/ROM programa
				cpu_data_r <= ram_data_r;
			elsif cpu_address(17 downto 16) = "01" then	--RAM dados
				cpu_data_r <= ram_data_r_dt;
			elsif cpu_address(17 downto 16) = "10" then	--RAM TCBs
				cpu_data_r <= ram_data_r_rt;
			else														--Área inválida
				cpu_data_r <= ZERO;			
			end if;
      
		--Acesso a RAM externa
		when "001" =>         --external RAM
         if cache_checking = '1' then				--Se o endereço foi carregado para cache
            cpu_data_r <= ram_data_r; --cache
         else												--Senão busca da memória externa DDR
            cpu_data_r <= data_read; --DDR	
         end if;
		
		--Acesso ao periféricos (LEITURA) <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
      when "010" =>         --misc
         --case cpu_address(6 downto 4) is	--Antes lia apenas 3 bits
         case cpu_address(7 downto 4) is	--Agora por conta do Microkernel lê 4 bits
         --UART
			when "0000" =>      --uart
            cpu_data_r <= ZERO(31 downto 8) & data_read_uart;
         --Máscara de interrupções
			when "0001" =>      --irq_mask
            cpu_data_r <= ZERO(31 downto 8) & irq_mask_reg;
         --Sataus das interrupções
			when "0010" =>      --irq_status
            cpu_data_r <= ZERO(31 downto 8) & irq_status;
         --Port de saída
			when "0011" =>      --gpio0
            cpu_data_r <= gpio0_reg;
         --Port de entrada
			when "0101" =>      --gpioA
            cpu_data_r <= gpioA_in;
         --Contador
			when "0110" =>      --counter
            cpu_data_r <= counter_reg;        
         --Em outros casos, o port de entrada é o padrão

			--Por alguma razão pulou o endereço da registrador Ethernet transmit count (0111)
			
			when "1000" =>      --Habilita o escalonador (0x20000080)
            cpu_data_r <= escalonador_rt_reg;
			when "1001" =>      --Tempo do tick em pulsos de clock (0x20000090)
            cpu_data_r <= tick_rt_reg;
			when "1010" =>      --Quantidade de tarefas (0x200000A0)
            cpu_data_r <= task_mumber_rt_reg;
			when "1011" =>      --Vetor de tarefas (existe/não existe, máx. 32) (0x200000B0)
            cpu_data_r <= task_live_rt_reg;	

			--Em outros casos, o port de entrada é o padrão
			when others =>
            cpu_data_r <= gpioA_in;	--0x20000050
         end case;
		
		--Memória flash 
      when "011" =>         --flash
         cpu_data_r <= data_read;
      
		--Em outros casos, leitura sempre 0
		when others =>
         cpu_data_r <= ZERO;
      end case;

		--Condição de reset
      if reset = '1' then
			--Limpa a máscara de interrupções
         irq_mask_reg <= ZERO(7 downto 0);
			--Zera o port de saída
         gpio0_reg <= ZERO;
			--Zera o contador
         counter_reg <= ZERO;
			
			--Microkernel <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
			--Desabilita o escalonador
			escalonador_rt_reg <= ZERO;
			--Zera o tempo do tick em pulsos de cloc
			tick_rt_reg	<= ZERO;
			--Zera a quantidade de tarefas
			task_mumber_rt_reg <= ZERO;
			--Mata todas as tarefas
			task_live_rt_reg <= ZERO;
			--Microkernel
			escalonador_rt_reg <= ZERO;	--Bit 0 deshabilita o escalonador
			tick_rt_reg <= ZERO;				--Tempo do tick em pulsos de clock = 0
			task_mumber_rt_reg <= ZERO; 	--Quantidade de tarefas = 0
			task_live_rt_reg <= ZERO; 		--Vetor de tarefas (existe/não existe, máx. 32) = não existem tarefas
			
      --Borda de subida do clock
		elsif rising_edge(clk) then
			--Acesso ao periféricos (ESCRITA)
			--Se a CPU não está apusada
         if cpu_pause = '0' then
				--Se os periféricos estão habilitados e há dado para escrita
            if enable_misc = '1' and write_enable = '1' then
					--Essa máscara era penas de 3 bits mas por conta do Microkernel passou para 4 bits<<<<<<<<<<<<<<<<<<<<<<
					--Se é o end. da máscara de interrupções
               if cpu_address(7 downto 4) = "0001" then
						--Atualiza seu valor
                  irq_mask_reg <= cpu_data_w(7 downto 0);
               --Senão se é o end. do port de saída para setar bits
					elsif cpu_address(7 downto 4) = "0011" then
						--Atualiza seu valor
                  gpio0_reg <= gpio0_reg or cpu_data_w;
               --Senão se é o end. do port de saída para resetar bits
					elsif cpu_address(7 downto 4) = "0100" then
						--Atualiza seu valor
                  gpio0_reg <= gpio0_reg and not cpu_data_w;
					--Senão se é o end. do Habilita o escalonador (0x20000080)
					elsif cpu_address(7 downto 4) = "1000" then
						--Atualiza seu valor
						escalonador_rt_reg <= cpu_data_w;
					--Senão se é o end. do Tempo do tick em pulsos de clock (0x20000090)
					elsif cpu_address(7 downto 4) = "1001" then
						--Atualiza seu valor
						tick_rt_reg <= cpu_data_w;
					--Senão se é o end. da Quantidade de tarefas (0x200000A0)
					elsif cpu_address(7 downto 4) = "1010" then
						--Atualiza seu valor
						task_mumber_rt_reg <= cpu_data_w;
					--Senão se é o end. do Vetor de tarefas (existe/não existe, máx. 32) (0x200000B0)
					elsif cpu_address(7 downto 4) = "1011" then
						--Atualiza seu valor
						task_live_rt_reg <= cpu_data_w;
						
               end if;
            end if;
         end if;
			--Incrementa o registador do contador
         counter_reg <= bv_inc(counter_reg);
      end if;
   end process;

	--Processo relacionado a sinais de escrita na memória
   ram_proc: process(cache_access, cache_miss,
                     address_next, cpu_address,
                     byte_we_next, cpu_data_w, data_read,
							escalonador_rt_reg(0))					--!!! Ajuste na lista de sensibilidade 28/12/16
   begin
		--Valor default para enable das rams !!! 28/12/16
		ram_enable_dt <= '0';
		ram_enable_rt <= '0';
		--Obs.: Operações com a cache não estão sendo sintetizadas!!!
		--Se for um acesso ao cache
      if cache_access = '1' then    --Check if cache hit or write through
         --Habilita a RAM
			ram_enable <= '1';
         --Conecta a saída de seleção dos bytes a escrever da CPU na memória RAM
			ram_byte_we <= byte_we_next;
			--Monta o endereço 0x0000 1xxx (1000 ~ 1FFC)
         ram_address(31 downto 2) <= ZERO(31 downto 16) & 
            "0001" & address_next(11 downto 2);
         --Conecta a saída de dados da para escrita da CPU na entrada de dados da memória RAM
			ram_data_w <= cpu_data_w;
		
		--Senão se ocorreu uma perda do cache e é proeciso de update
      elsif cache_miss = '1' then  --Update cache after cache miss
         --Habilita a RAM
			ram_enable <= '1';
			--Força escrita de todos os bytes
         ram_byte_we <= "1111";
         --Monta o endereço 0x0000 1xxx (1000 ~ 1FFC)
			ram_address(31 downto 2) <= ZERO(31 downto 16) & 
            "0001" & cpu_address(11 downto 2);
         --Conecta a entrada de dados da memória externa na entrada de dados da memória RAM
			ram_data_w <= data_read;
      
		--Senão é uma acesso a memória não-cache
		else                         --Normal non-cache access
			--Se está na faixa da RAM/ROM interna para programa <<<<<<<<<<<<<<<<<<
			if address_next(30 downto 28) = "000"  and  address_next(17 downto 16) = "00" then
            --Habilita a memória RAM/ROM para programa
				ram_enable <= '1';
         --Senão
			else
				--Desabilita a memória RAM/ROM para programa
            ram_enable <= '0';
         end if;
			--Se está na faixa da RAM interna para dados <<<<<<<<<<<<<<<<<<<<<<<<<
			if address_next(30 downto 28) = "000"  and  address_next(17 downto 16) = "01" then
            --Habilita a memória RAM para dados
				ram_enable_dt <= '1';
         --Senão
			else
				--Desabilita a memória RAM para dados
            ram_enable_dt <= '0';
         end if;
			--Se está na faixa da RAM interna para TCBs e o escalonador está desabilitado <<<<<<<<<<<<
			--ou se o escalonador está habilitado (neste caso é acessada pelo Microkernel)
			if (address_next(30 downto 28) = "000"  and  address_next(17 downto 16) = "10" and escalonador_rt_reg(0) = '0') or escalonador_rt_reg(0) = '1' then
            --Habilita a memória RAM para TCBs
				ram_enable_rt <= '1';
         --Senão
			else
				--Desabilita a memória RAM para TCBs
            ram_enable_rt <= '0';
         end if;
      end if;
				
		--A conexão para as memórias de programa e dados é paralela <<<<<<<<<<
		
		--Conecta a saída de seleção dos bytes a escrever da CPU na memória RAM
		ram_byte_we <= byte_we_next;
		ram_byte_we_dt <= byte_we_next;
		--Conecta a saída de endereço da CPU na memória RAM
		--address_next não depende do final de processo para atualizar
		ram_address(31 downto 2) <= address_next(31 downto 2);
		ram_address_dt(31 downto 2) <= address_next(31 downto 2);
		--Conecta a saída de dados para escrita da CPU na entrada de dados da memória RAM
		ram_data_w <= cpu_data_w;
		ram_data_w_dt <= cpu_data_w;
   end process;

	--Multiplex dos sinais de entrada <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
		ram_byte_we_rt <= byte_we_next when escalonador_rt_reg(0) = '0' 
					else mk_byte_we;
		ram_address_rt(31 downto 2) <= address_next(31 downto 2) when escalonador_rt_reg(0) = '0' 
					else mk_address(31 downto 2);
		ram_data_w_rt <= cpu_data_w when escalonador_rt_reg(0) = '0' 
					else mk_data_w;
	
	--Multiplex dos sinais de saída <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
		mk_data_r <= ram_data_r_rt;	--A saída da memória sempre é encaminhada para o microkernel
	
   u2_ram: ram 
      generic map (memory_type => memory_type)
      port map (
         clk               => clk,
         enable            => ram_enable,
         write_byte_enable => ram_byte_we,
         address           => ram_address,
         data_write        => ram_data_w,
         data_read         => ram_data_r);
			
	u3_ram_dt: ram 
      generic map (memory_type => memory_type)
      port map (
         clk               => clk,
         enable            => ram_enable_dt,
         write_byte_enable => ram_byte_we_dt,
         address           => ram_address_dt,
         data_write        => ram_data_w_dt,
         data_read         => ram_data_r_dt);
	
	u4_ram_rt: ram 
      generic map (memory_type => memory_type)
      port map (
         clk               => clk,
         enable            => ram_enable_rt,
         write_byte_enable => ram_byte_we_rt,
         address           => ram_address_rt,
         data_write        => ram_data_w_rt,
         data_read         => ram_data_r_rt);

	--u3_uart: uart
   u5_uart: uart
      generic map (log_file => log_file)
      port map(
         clk          => clk,
         reset        => reset,
         enable_read  => enable_uart_read,
         enable_write => enable_uart_write,
         data_in      => cpu_data_w(7 downto 0),
         data_out     => data_read_uart,
         uart_read    => uart_read,
         uart_write   => uart_write,
         busy_write   => uart_write_busy,
         data_avail   => uart_data_avail);

   dma_gen: if ethernet = '0' generate
      address <= cpu_address(31 downto 2);
      byte_we <= cpu_byte_we;
      data_write <= cpu_data_w;
      eth_pause <= '0';
      gpio0_out(28 downto 24) <= ZERO(28 downto 24);
      irq_eth_rec <= '0';
      irq_eth_send <= '0';
   end generate;

   dma_gen2: if ethernet = '1' generate
   u6_eth: eth_dma 
      port map(
         clk         => clk,
         reset       => reset,
         enable_eth  => gpio0_reg(24),
         select_eth  => enable_eth,
         rec_isr     => irq_eth_rec,
         send_isr    => irq_eth_send,

         address     => address,      --to DDR
         byte_we     => byte_we,
         data_write  => data_write,
         data_read   => data_read,
         pause_in    => eth_pause_in,

         mem_address => cpu_address(31 downto 2), --from CPU
         mem_byte_we => cpu_byte_we,
         data_w      => cpu_data_w,
         pause_out   => eth_pause,

         E_RX_CLK    => gpioA_in(20),
         E_RX_DV     => gpioA_in(19),
         E_RXD       => gpioA_in(18 downto 15),
         E_TX_CLK    => gpioA_in(14),
         E_TX_EN     => gpio0_out(28),
         E_TXD       => gpio0_out(27 downto 24));
   end generate;
	
	u7_microkernel: microkernel
		port map (
			clk          			=> clk,
			reset_in     			=> reset,
			counter					=> counter_reg,

			--Configuração e uso do escalonador
			escalonador  			=> escalonador_rt_reg(0 downto 0),		--Bit 0 habilita o escalonador
			tick			 			=> tick_rt_reg, 					--Tempo do tick em pulsos de clock
			task_mumber				=> task_mumber_rt_reg,			--Quantidade de tarefas
			task_live	 			=> task_live_rt_reg,				--Vetor de tarefas (existe/não existe, máx. 32)			
			
			--Microkernel conectado ao bloco pc_next_RT (POR ENQUANTO NÃO TEM NADA LIGADO)
		   pc_RT  					=>	pc_RT,					--30 bits para jump desvio de tarefa
		   task_switch_RT 		=>	task_switch_RT,		--Força a troca de tarefa
			pc_backup_RT			=>	pc_backup_RT,			--30 bits com o endereço da próxima instrução sem considerar troca de tarefa
			
			--Microkernel conectado ao bloco reg_bank_duplo_RT (POR ENQUANTO NÃO TEM NADA LIGADO)
			rs_index_RT       	=> rs_index_RT,
			rt_index_RT       	=> rt_index_RT,
			rd_index_RT       	=> rd_index_RT,
			reg_source_out_RT 	=> reg_source_out_RT,
			reg_target_out_RT 	=> reg_target_out_RT,
			reg_dest_new_RT   	=> reg_dest_new_RT,
			intr_enable_RT    	=> intr_enable_RT,
		  
			sel_bank_RT				=> sel_bank_RT,			--0/1 inverte o banco utilizado pela CPU
			
			--Microkernel conectado as fontes de pause da CPU
		   pause_RT					=> pause_RT,
			
			--Microkernel conectado ao bloco control
			switch_out_RT			=> switch_out_RT,
			
			--Microkernel conectado ao bloco ram_rt
			mk_address       		=> mk_address,				--Microkernel - endereço da memória RAM TCB
			mk_byte_we       		=> mk_byte_we,				--Microkernel - bytes para escrita na memória RAM TCB
			mk_data_w        		=> mk_data_w,				--Microkernel - dado para escrita na RAM TCB
			mk_data_r        		=> mk_data_r,				--Microkernel - dado para leitura na RAM TCB
			
			--Saída para depuração (criado em 24/11/16)
			mk_debug					=> mk_debug
		);

end; --architecture logic

