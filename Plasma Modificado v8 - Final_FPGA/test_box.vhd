
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;

entity test_box is
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
		  mk_debug					: out std_logic_vector(15 downto 0)	--alterado para 16 bits (21/05/17)
		  );
end; --entity plasma_RT

architecture logic of test_box is
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
	signal escalonador_rt_reg	: std_logic_vector(31 downto 0);	--Bit 0 habilita o escalonador
	signal tick_rt_reg			: std_logic_vector(31 downto 0);	--Tempo do tick em pulsos de clock
	signal task_number_rt_reg	: std_logic_vector(31 downto 0);	--Quantidade de tarefas
	signal task_live_rt_reg		: std_logic_vector(31 downto 0);	--Vetor de tarefas (existe/não existe, máx. 32)
	signal task_pri7_0_reg		: std_logic_vector(31 downto 0); --Vetor de prioridade das tarefas 7~0 (4 bits por tarefa)
	signal task_pri15_8_reg		: std_logic_vector(31 downto 0); --Vetor de prioridade das tarefas 15~8
	signal task_pri23_16_reg	: std_logic_vector(31 downto 0); --Vetor de prioridade das tarefas 23~16
	signal task_pri31_24_reg	: std_logic_vector(31 downto 0); --Vetor de prioridade das tarefas 32~24
	signal task_sleep_reg		: std_logic_vector(31 downto 0); --Tempo de sleep ou yield da tarefa atual
	
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
	u7_microkernel: microkernel
		port map (
			clk          			=> clk,
			reset_in     			=> reset,
			counter					=> counter_reg,

			--Configuração e uso do escalonador
			escalonador  			=> escalonador_rt_reg(0 downto 0),		--Bit 0 habilita o escalonador
			tick			 			=> tick_rt_reg, 					--Tempo do tick em pulsos de clock
			task_number				=> task_number_rt_reg,			--Quantidade de tarefas
			task_live	 			=> task_live_rt_reg,				--Vetor de tarefas (existe/não existe, máx. 32)			
			task_pri7_0				=> task_pri7_0_reg,				--Vetor de prioridade das tarefas 7~0 (4 bits por tarefa)
			task_pri15_8			=> task_pri15_8_reg,				--Vetor de prioridade das tarefas 15~8
			task_pri23_16			=> task_pri23_16_reg,			--Vetor de prioridade das tarefas 23~16
			task_pri31_24			=> task_pri31_24_reg,			--Vetor de prioridade das tarefas 31~24
			task_sleep				=> task_sleep_reg,				--Tempo de sleep ou yield da tarefa atual
			
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

