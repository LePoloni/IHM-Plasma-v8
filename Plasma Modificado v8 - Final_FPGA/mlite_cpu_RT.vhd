---------------------------------------------------------------------
-- TITLE: Plasma CPU core
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 2/15/01
-- FILENAME: mlite_cpu.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- NOTE:  MIPS(tm) and MIPS I(tm) are registered trademarks of MIPS 
--    Technologies.  MIPS Technologies does not endorse and is not 
--    associated with this project.
-- DESCRIPTION:
--    Top level VHDL document that ties the nine other entities together.
--
-- Executes all MIPS I(tm) opcodes but exceptions and non-aligned
-- memory accesses.  Based on information found in:
--    "MIPS RISC Architecture" by Gerry Kane and Joe Heinrich
--    and "The Designer's Guide to VHDL" by Peter J. Ashenden
--
-- The CPU is implemented as a two or three stage pipeline.
-- An add instruction would take the following steps (see cpu.gif):
-- Stage #0:
--    1.  The "pc_next" entity passes the program counter (PC) to the 
--        "mem_ctrl" entity which fetches the opcode from memory.
-- Stage #1:
--    2.  The memory returns the opcode.
-- Stage #2:
--    3.  "Mem_ctrl" passes the opcode to the "control" entity.
--    4.  "Control" converts the 32-bit opcode to a 60-bit VLWI opcode
--        and sends control signals to the other entities.
--    5.  Based on the rs_index and rt_index control signals, "reg_bank" 
--        sends the 32-bit reg_source and reg_target to "bus_mux".
--    6.  Based on the a_source and b_source control signals, "bus_mux"
--        multiplexes reg_source onto a_bus and reg_target onto b_bus.
-- Stage #3 (part of stage #2 if using two stage pipeline):
--    7.  Based on the alu_func control signals, "alu" adds the values
--        from a_bus and b_bus and places the result on c_bus.
--    8.  Based on the c_source control signals, "bus_bux" multiplexes
--        c_bus onto reg_dest.
--    9.  Based on the rd_index control signal, "reg_bank" saves
--        reg_dest into the correct register.
-- Stage #3b:
--   10.  Read or write memory if needed.
--
-- All signals are active high. 
-- Here are the signals for writing a character to address 0xffff
-- when using a two stage pipeline:
--
-- Program:
-- addr     value  opcode 
-- =============================
--   3c: 00000000  nop
--   40: 34040041  li $a0,0x41
--   44: 3405ffff  li $a1,0xffff
--   48: a0a40000  sb $a0,0($a1)
--   4c: 00000000  nop
--   50: 00000000  nop
--
--      intr_in                             mem_pause 
--  reset_in                               byte_we     Stages
--     ns         address     data_w     data_r        40 44 48 4c 50
--   3600  0  0  00000040   00000000   34040041  0  0   1  
--   3700  0  0  00000044   00000000   3405FFFF  0  0   2  1  
--   3800  0  0  00000048   00000000   A0A40000  0  0      2  1  
--   3900  0  0  0000004C   41414141   00000000  0  0         2  1
--   4000  0  0  0000FFFC   41414141   XXXXXX41  1  0         3  2  
--   4100  0  0  00000050   00000000   00000000  0  0               1

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 14/7/16
-- ALTERADO: 
--	2/11/16 - Versão 2 - Inclusão do componente 
-- alu_mult_shifter que substitui os componetes alu, mult e shifter.
-- Craido a partir do arquivo mlite_cpu_mod
-- 30/11/16 - Alterado u3_control: control PORT MAP
--				- Criado os sinais
--						signal task_switch_signal	: std_logic;				--Pedido para troca de tarefa
--						signal switch_out		 : std_logic);						--Sinalização de troca de tarefa
--				- Tratamento de pedido para troca de tarefa (próximo linhas 200 e 250)
-- 23/12/16 - Alterada a lista de sensibilidade do processo responsável pelo pedido de troca de tarefas
--						(próximo da linha 222)
--	28/12/16 - Organização do código do processo backup_do_pc
--				- Removida a saída mem_source_RT		: out mem_source_type; não foi usada pelo Microkernel
-- 23/01/18 - O processo backup_do_pc (linha ~266) precisou ser dividido em 2 por conta
--				  dele trabalhar com as duas bordas do clock e o Encounter (Cadence) não suportar
--				  processos com essas características.
-- 13/03/18 - Correção no processo backup_do_pc (linha ~266) que pecisou ser dividido em
--				  em 2 para rodar no RTL Compiler e Encounter mas estava usando uma variável
--				  local que foi substituida por um sinal.
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use work.mlite_pack_mod.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity mlite_cpu_RT is
   --generic(memory_type     : string  := "XILINX_16X"; --ALTERA_LPM, or DUAL_PORT_	--LEANDRO: Comentei
	generic(memory_type : string := "ALTERA_LPM"; --LEANDRO: Criei
	mult_type       : string  := "DEFAULT"; --AREA_OPTIMIZED
           shifter_type    : string  := "DEFAULT"; --AREA_OPTIMIZED
           alu_type        : string  := "DEFAULT"; --AREA_OPTIMIZED
           pipeline_stages : natural := 2); --2 or 3
   port(clk          : in std_logic;
        reset_in     : in std_logic;
        intr_in      : in std_logic;									--Flag de sinalização de interrupção habilitada e ativa

        address_next : out std_logic_vector(31 downto 2); --for synch ram
        byte_we_next : out std_logic_vector(3 downto 0); 

        address      : out std_logic_vector(31 downto 2);
        byte_we      : out std_logic_vector(3 downto 0);
        data_w       : out std_logic_vector(31 downto 0);
        data_r       : in 	std_logic_vector(31 downto 0);
        mem_pause    : in 	std_logic;
		  
		  --Microkernel conectado ao bloco pc_next_RT
		  pc_RT		  		: in 	std_logic_vector(31 downto 2);		--30 bits para jump desvio de tarefa
		  task_switch_RT 	: in 	std_logic;									--Força a troca de tarefa
		  pc_backup_RT		: out std_logic_vector(31 downto 2);		--30 bits com o endereço da próxima instrução sem considerar troca de tarefa
		  escalonador_RT	: in	std_logic;									--Sinalização do estado do escalonador
		  
		  --Microkernel conectado ao bloco reg_bank_duplo_RT
		  rs_index_RT       	: in  std_logic_vector(5 downto 0);		--End. fonte de dados (6 bits ao invés de 5)
        rt_index_RT       	: in  std_logic_vector(5 downto 0);		--End. fonte de ou destino de dados
        rd_index_RT       	: in  std_logic_vector(5 downto 0);		--End. destino de dados
        reg_source_out_RT 	: out std_logic_vector(31 downto 0);	--Saída de dados de acordo com rs
        reg_target_out_RT 	: out std_logic_vector(31 downto 0);	--Saída de dados de acordo com rt
        reg_dest_new_RT   	: in  std_logic_vector(31 downto 0);	--Entrada de dados de acordo com rd
		  intr_enable_RT    	: out std_logic;								--Flag de enable de interrupção
		  
		  sel_bank_RT			: in  std_logic;								--Seleciona o banco utilizado pela CPU
		  
		  --Microkernel conectado as fontes de pause da CPU
		  pause_RT				: out std_logic;
		  
		  --Microkernel conectado ao bloco control
		  switch_out_RT		: out std_logic;								--Sinaliza pedido de switch em atendimento
		  
		  --Debug genérico da CPU
		  debug_cpu				: out std_logic_vector(31 downto 2));
		  
end; --entity mlite_RT

architecture logic of mlite_cpu_RT is
   --When using a two stage pipeline "sigD <= sig".
   --When using a three stage pipeline "sigD <= sig when rising_edge(clk)",
   --  so sigD is delayed by one clock cycle.
   signal opcode         : std_logic_vector(31 downto 0);
   signal rs_index       : std_logic_vector(5 downto 0);
   signal rt_index       : std_logic_vector(5 downto 0);
   signal rd_index       : std_logic_vector(5 downto 0);
   signal rd_indexD      : std_logic_vector(5 downto 0);
   signal reg_source     : std_logic_vector(31 downto 0);
   signal reg_target     : std_logic_vector(31 downto 0);
   signal reg_dest       : std_logic_vector(31 downto 0);
   signal reg_destD      : std_logic_vector(31 downto 0);
   signal a_bus          : std_logic_vector(31 downto 0);
   signal a_busD         : std_logic_vector(31 downto 0);
   signal b_bus          : std_logic_vector(31 downto 0);
   signal b_busD         : std_logic_vector(31 downto 0);
   signal c_bus          : std_logic_vector(31 downto 0);
   signal c_alu          : std_logic_vector(31 downto 0);
   signal c_shift        : std_logic_vector(31 downto 0);
   signal c_mult         : std_logic_vector(31 downto 0);
   signal c_memory       : std_logic_vector(31 downto 0);
   signal imm            : std_logic_vector(15 downto 0);
   signal pc_future      : std_logic_vector(31 downto 2);
   signal pc_current     : std_logic_vector(31 downto 2);
   signal pc_plus4       : std_logic_vector(31 downto 2);
   signal alu_func       : alu_function_type;
   signal alu_funcD      : alu_function_type;
   signal shift_func     : shift_function_type;
   signal shift_funcD    : shift_function_type;
   signal mult_func      : mult_function_type;
   signal mult_funcD     : mult_function_type;
   signal branch_func    : branch_function_type;
   signal take_branch    : std_logic;
   signal a_source       : a_source_type;
   signal b_source       : b_source_type;
   signal c_source       : c_source_type;
   signal pc_source      : pc_source_type;
   signal mem_source     : mem_source_type;
   signal pause_mult     : std_logic;
   signal pause_ctrl     : std_logic;
   signal pause_pipeline : std_logic;
   signal pause_any      : std_logic;
   signal pause_non_ctrl : std_logic;
   signal pause_bank     : std_logic;
   signal nullify_op     : std_logic;
   signal intr_enable    : std_logic;
   signal intr_signal    : std_logic;
   signal exception_sig  : std_logic;
	--Correção 13/03/18
	signal pc_current_abortado: std_logic_vector(31 downto 2);
	--NÃO PRECISA MAIS PORQUE ESTOU USANDO O COMPOENTE reset_controller
--   signal reset_reg      : std_logic_vector(3 downto 0);
   signal reset          : std_logic;
	
	signal task_switch_signal	: std_logic;			--Pedido para troca de tarefa
	signal switch_out		 : std_logic;					--Sinalização de troca de tarefa
begin  --architecture

	--Monitora o valor de pc_current
	debug_cpu <= pc_current;

	--Ativa pause_any se houver pedido da memória ou do mem_ctrl ou do mult ou do pipeline (3 estágios)
   pause_any <= (mem_pause or pause_ctrl) or (pause_mult or pause_pipeline);
	--Ativa pause_non_ctrl se houver pedido da memória ou do mult ou do pipeline (3 estágios)
   pause_non_ctrl <= (mem_pause or pause_mult) or pause_pipeline;
	--Ativa pause_bank se houver pedido da memória ou do mem_ctrl ou do mult ou não do pipeline (3 estágios)
   pause_bank <= (mem_pause or pause_ctrl or pause_mult) and not pause_pipeline;
   --Força operação nula quando ocorrer um long branch e não ocorrer pedido de desvio
	--ou ocorrer um pedido de interrupção ou exceção ou troca de tarefa
	nullify_op <= '1' when (pc_source = FROM_LBRANCH and take_branch = '0')
                          or intr_signal = '1' or exception_sig = '1'
								  or task_switch_signal = '1' or switch_out = '1'
                          else '0';
	
	--Sinaliza o Microkernel que a CPU está parada finalizando a execusão de alguma operação
	pause_RT <= pause_any;
	--Sinaliza o Micrikernel que a CPU está tratando o pedido de stroca de tarefa
	switch_out_RT <= switch_out;
								  
   --Sincroniza o reset, pinos de interrupção e troca de tarefa (real-time)
	intr_proc: process(clk, reset_in, intr_in, intr_enable, task_switch_RT, escalonador_RT,
      pc_source, pc_current, pause_any)
   begin
	
		--ALGUMAS LINHAS NÃO SÃO MAIS NECESSÁRIAS PORQUE ESTOU USANDO O COMPOENTE reset_controller
			
		--Se a entrada de reset = 1
      if reset_in = '1' then
         intr_signal <= '0';
		--Senão se ocorrer uma borda de subida do clock
      elsif rising_edge(clk) then
         --don't try to interrupt a multi-cycle instruction
         --Se não ha condição para o pause
			if pause_any = '0' then
				--Se a entrada de interrupção externa está ativadoa e as interupções estão habilitadas e 
				--PC vai para próxima instrução
            if intr_in = '1' and intr_enable = '1' and 
               pc_source = FROM_INC4 then
               --the epc will contain pc+4
					--Ativa a flag de interrupção (enviado para control e nullify_op)
					intr_signal <= '1';
            --Senão
				else
					--Desativa a flag de interrupção
               intr_signal <= '0';
            end if;
				
				--Tratamento de pedido para troca de tarefa
				--Se tem um pedido de troca de tarefa e o escalonador está ligado e a fonte da próxima instrução
				--é igual a PC+4
				if task_switch_RT = '1' and escalonador_RT = '1' and 
						pc_source = FROM_INC4 then
					--Ativa a flag cmo pedido de troca de tarefa
					task_switch_signal <= '1';
				else
					--Desativa a flag com pedido de troca de tarefa
					task_switch_signal <= '0';
				end if;
				
         end if;

      end if;
   end process;
	
	--A ideia é pegar a instrução anterior que foi abortada
	--Se usar pc_current_abortado pela a instrução que não foi executada
	--Se usar pc_current perde uma instrução
	backup_do_pc: process(clk, pc_current)
--	variable pc_current_abortado: std_logic_vector(31 downto 2);
	begin
		if rising_edge(clk) then
			--pc_current_abortado := pc_current;			--Grava o valor antigo
			pc_current_abortado <= pc_current;			--Grava o valor antigo
		end if;
	end process;
	
	--Separado em dois processos um para cada borda para compatibilizar com
	--o Encounter (Cadence)
	backup_do_pc2: process(clk, task_switch_signal, switch_out)
--	variable pc_current_abortado: std_logic_vector(31 downto 2);
	begin
		if task_switch_signal = '1' and switch_out = '1' then
			if falling_edge(clk) then
				pc_backup_RT <= pc_current_abortado;	--Faz backup do valor antigo
			end if;
		end if;	
	end process;

--NÃO PRECISA MAIS PORQUE ESTOU USANDO O COMPONENTE pc_next_RT
--   u1_pc_next: pc_next PORT MAP (
--        clk          => clk,
--        reset_in     => reset,
--        take_branch  => take_branch,
--        pause_in     => pause_any,
--        pc_new       => c_bus(31 downto 2),
--        opcode25_0   => opcode(25 downto 0),
--        pc_source    => pc_source,
--        pc_future    => pc_future,
--        pc_current   => pc_current,
--        pc_plus4     => pc_plus4);
		  
	u1_pc_next_RT: pc_next_RT PORT MAP (
        clk          => clk,
        reset_in     => reset,
        take_branch  => take_branch,
        pause_in     => pause_any,
        pc_new       => c_bus(31 downto 2),
        opcode25_0   => opcode(25 downto 0),
        pc_source    => pc_source,
        pc_future    => pc_future,
        pc_current   => pc_current,
        pc_plus4     => pc_plus4,
		  --Microkernel
		  pc_RT  		=>	pc_RT,						--30 bits para jump desvio de tarefa
		  task_switch_RT =>	task_switch_RT);		--Força a troca de tarefa
		  
   u2_mem_ctrl: mem_ctrl 
      PORT MAP (
        clk          => clk,
        reset_in     => reset,
        pause_in     => pause_non_ctrl,
        nullify_op   => nullify_op,
        address_pc   => pc_future,
        opcode_out   => opcode,

        address_in   => c_bus,
        mem_source   => mem_source,
        data_write   => reg_target,
        data_read    => c_memory,
        pause_out    => pause_ctrl,
        
        address_next => address_next,
        byte_we_next => byte_we_next,

        address      => address,
        byte_we      => byte_we,
        data_w       => data_w,
        data_r       => data_r);

   u3_control: control PORT MAP (
        opcode       => opcode,
        intr_signal  => intr_signal,
        rs_index     => rs_index,
        rt_index     => rt_index,
        rd_index     => rd_index,
        imm_out      => imm,
        alu_func     => alu_func,
        shift_func   => shift_func,
        mult_func    => mult_func,
        branch_func  => branch_func,
        a_source_out => a_source,
        b_source_out => b_source,
        c_source_out => c_source,
        pc_source_out=> pc_source,
        mem_source_out=> mem_source,
        exception_out=> exception_sig,
		  task_switch_signal	=> task_switch_signal,			--Pedido para troca de tarefa
		  switch_out			=> switch_out						--Sinalização de troca de tarefa
		  );

--NÃO PRECISA MAIS PORQUE ESTOU USANDO O COMPOENTE u4_reg_bank_RT
--   u4_reg_bank: reg_bank 
--      generic map(memory_type => memory_type)
--      port map (
--        clk            => clk,
--        reset_in       => reset,
--        pause          => pause_bank,
--        rs_index       => rs_index,
--        rt_index       => rt_index,
--        rd_index       => rd_indexD,
--        reg_source_out => reg_source,
--        reg_target_out => reg_target,
--        reg_dest_new   => reg_destD,
--        intr_enable    => intr_enable);

	u4_reg_bank_duplo_RT: reg_bank_duplo_RT
		generic map(memory_type => memory_type)
		port map (
		  clk            => clk,
        reset_in       => reset,
        pause          => pause_bank,
        
		  rs_index_cpu       => rs_index,
        rt_index_cpu       => rt_index,
        rd_index_cpu       => rd_indexD,
        reg_source_out_cpu => reg_source,
        reg_target_out_cpu => reg_target,
        reg_dest_new_cpu   => reg_destD,
		  intr_enable_cpu    => intr_enable,
		  --Sinais usados pelo Microkernel
		  rs_index_RT       	=> rs_index_RT,
        rt_index_RT       	=> rt_index_RT,
        rd_index_RT       	=> rd_index_RT,
        reg_source_out_RT 	=> reg_source_out_RT,
        reg_target_out_RT 	=> reg_target_out_RT,
        reg_dest_new_RT   	=> reg_dest_new_RT,
		  intr_enable_RT    	=> intr_enable_RT,
		  
		  sel_bank_RT			=> sel_bank_RT);

   u5_bus_mux: bus_mux port map (
        imm_in       => imm,
        reg_source   => reg_source,
        a_mux        => a_source,
        a_out        => a_bus,

        reg_target   => reg_target,
        b_mux        => b_source,
        b_out        => b_bus,

        c_bus        => c_bus,
        c_memory     => c_memory,
        c_pc         => pc_current,
        c_pc_plus4   => pc_plus4,
        c_mux        => c_source,
        reg_dest_out => reg_dest,

        branch_func  => branch_func,
        take_branch  => take_branch);

--NÃO PRECISA MAIS PORQUE ESTOU USANDO O COMPOENTE alu_mult_shifter
--   u6_alu: alu 
--      generic map (alu_type => alu_type)
--      port map (
--        a_in         => a_busD,
--        b_in         => b_busD,
--        alu_function => alu_funcD,
--        c_alu        => c_alu);
--
--   u7_shifter: shifter
--      generic map (shifter_type => shifter_type)
--      port map (
--        value        => b_busD,
--        shift_amount => a_busD(4 downto 0),
--        shift_func   => shift_funcD,
--        c_shift      => c_shift);
--
--   u8_mult: mult 
--      generic map (mult_type => mult_type)
--      port map (
--        clk       => clk,
--        reset_in  => reset,
--        a         => a_busD,
--        b         => b_busD,
--        mult_func => mult_funcD,
--        c_mult    => c_mult,
--        pause_out => pause_mult);
	
	u678_alu_mult_shifter: alu_mult_shifter
		generic map(	alu_type 	=> alu_type,
							mult_type 	=> mult_type,
							shifter_type => shifter_type)
		port map (
		  clk       => clk,
        reset_in  => reset,
        a_in      => a_busD,
        b_in      => b_busD,
		  alu_func 	=> alu_funcD,
		  mult_func => mult_funcD,
		  shift_func   => shift_funcD,
		  c_out		=> c_bus,
		  pause_out => pause_mult);

   pipeline2: if pipeline_stages <= 2 generate
      a_busD <= a_bus;
      b_busD <= b_bus;
      alu_funcD <= alu_func;
      shift_funcD <= shift_func;
      mult_funcD <= mult_func;
      rd_indexD <= rd_index;
      reg_destD <= reg_dest;
      pause_pipeline <= '0';
   end generate; --pipeline2

   pipeline3: if pipeline_stages > 2 generate
      --When operating in three stage pipeline mode, the following signals
      --are delayed by one clock cycle:  a_bus, b_bus, alu/shift/mult_func,
      --c_source, and rd_index.
   u9_pipeline: pipeline port map (
        clk            => clk,
        reset          => reset,
        a_bus          => a_bus,
        a_busD         => a_busD,
        b_bus          => b_bus,
        b_busD         => b_busD,
        alu_func       => alu_func,
        alu_funcD      => alu_funcD,
        shift_func     => shift_func,
        shift_funcD    => shift_funcD,
        mult_func      => mult_func,
        mult_funcD     => mult_funcD,
        reg_dest       => reg_dest,
        reg_destD      => reg_destD,
        rd_index       => rd_index,
        rd_indexD      => rd_indexD,

        rs_index       => rs_index,
        rt_index       => rt_index,
        pc_source      => pc_source,
        mem_source     => mem_source,
        a_source       => a_source,
        b_source       => b_source,
        c_source       => c_source,
        c_bus          => c_bus,
        pause_any      => pause_any,
        pause_pipeline => pause_pipeline);

   end generate; --pipeline3
	
	u10_reset_controller: reset_controller
	port map (
		clk       => clk,
		reset_in  => reset_in,
		reset_out => reset);

end; --architecture logic
