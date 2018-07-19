---------------------------------------------------------------------
-- TITLE: Register Bank Duplo RT
-- AUTHOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATE CREATED: 21/09/2016
-- FILENAME: reg_bank_duplo_RT.vhd
-- PROJECT: Plasma CPU Modificado core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Implements a register bank with 32 registers that are 32-bits wide.
--    There are two read-ports and one write port.

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 
-- MOVIFICADO:
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.mlite_pack_mod.all;
--library UNISIM;               --May need to uncomment for ModelSim
--use UNISIM.vcomponents.all;   --May need to uncomment for ModelSim

entity reg_bank_duplo_RT is
   --generic(memory_type 		: string := "ALTERA_LPM");
	generic(memory_type 		: string := "TRI_PORT_X");
   port(clk            		: in  std_logic;
        reset_in       		: in  std_logic;
        pause          		: in  std_logic;
        
		  rs_index_cpu       : in  std_logic_vector(5 downto 0);		--End. fonte de dados (6 bits ao invés de 5)
        rt_index_cpu       : in  std_logic_vector(5 downto 0);		--End. fonte de ou destino de dados
        rd_index_cpu       : in  std_logic_vector(5 downto 0);		--End. destino de dados
        reg_source_out_cpu : out std_logic_vector(31 downto 0);	--Saída de dados de acordo com rs
        reg_target_out_cpu : out std_logic_vector(31 downto 0);	--Saída de dados de acordo com rt
        reg_dest_new_cpu   : in  std_logic_vector(31 downto 0);	--Entrada de dados de acordo com rd
		  intr_enable_cpu    : out std_logic;								--Flag de enable de interrupção
		  --Sinais usados pelo Microkernel
		  rs_index_RT       	: in  std_logic_vector(5 downto 0);		--End. fonte de dados (6 bits ao invés de 5)
        rt_index_RT       	: in  std_logic_vector(5 downto 0);		--End. fonte de ou destino de dados
        rd_index_RT       	: in  std_logic_vector(5 downto 0);		--End. destino de dados
        reg_source_out_RT 	: out std_logic_vector(31 downto 0);	--Saída de dados de acordo com rs
        reg_target_out_RT 	: out std_logic_vector(31 downto 0);	--Saída de dados de acordo com rt
        reg_dest_new_RT   	: in  std_logic_vector(31 downto 0);	--Entrada de dados de acordo com rd
		  intr_enable_RT    	: out std_logic;								--Flag de enable de interrupção
		  
		  sel_bank_RT			: in  std_logic);								--Seleciona o banco utilizado pela CPU						
		  
end; --entity reg_bank_duplo_RT

--------------------------------------------------------------------
-- The ram_block architecture attempts to use TWO dual-port memories.
-- Different FPGAs and ASICs need different implementations.
-- Choose one of the RAM implementations below.
-- I need feedback on this section!
--------------------------------------------------------------------

--Pelo que entendi o 6o bit do endereçamento define se é um registrador da CPU (0)
--ou do coprocessador 0 (1)

architecture ram_block of reg_bank_duplo_RT is
	 
	signal rs_index_1       : std_logic_vector(5 downto 0);		--End. fonte de dados (6 bits ao invés de 5)
   signal rt_index_1       : std_logic_vector(5 downto 0);		--End. fonte de ou destino de dados
   signal rd_index_1       : std_logic_vector(5 downto 0);		--End. destino de dados
   signal reg_source_out_1 : std_logic_vector(31 downto 0);	--Saída de dados de acordo com rs
   signal reg_target_out_1 : std_logic_vector(31 downto 0);	--Saída de dados de acordo com rt
   signal reg_dest_new_1   : std_logic_vector(31 downto 0);	--Entrada de dados de acordo com rd
	signal intr_enable_1    : std_logic;								--Flag de enable de interrupção
		  --Sinais referentes ao segundo banco de registradores
	signal rs_index_2       : std_logic_vector(5 downto 0);		--End. fonte de dados (6 bits ao invés de 5)
   signal rt_index_2       : std_logic_vector(5 downto 0);		--End. fonte de ou destino de dados
   signal rd_index_2       : std_logic_vector(5 downto 0);		--End. destino de dados
   signal reg_source_out_2 : std_logic_vector(31 downto 0);	--Saída de dados de acordo com rs
   signal reg_target_out_2 : std_logic_vector(31 downto 0);	--Saída de dados de acordo com rt
   signal reg_dest_new_2   : std_logic_vector(31 downto 0);	--Entrada de dados de acordo com rd
	signal intr_enable_2    : std_logic;								--Flag de enable de interrupção
	
	signal reg_sel_bank_RT	: std_logic;								--Seleciona o banco utilizado pela CPU	
	
begin

	u1_reg_bank: reg_bank
      generic map(memory_type => memory_type)
      port map (
        clk            => clk,
        reset_in       => reset_in,
        pause          => pause,
        rs_index       => rs_index_1,
        rt_index       => rt_index_1,
        rd_index       => rd_index_1,
        reg_source_out => reg_source_out_1,
        reg_target_out => reg_target_out_1,
        reg_dest_new   => reg_dest_new_1,
        intr_enable    => intr_enable_1);

	u2_reg_bank: reg_bank 
      generic map(memory_type => memory_type)
      port map (
        clk            => clk,
        reset_in       => reset_in,
        pause          => pause,
        rs_index       => rs_index_2,
        rt_index       => rt_index_2,
        rd_index       => rd_index_2,
        reg_source_out => reg_source_out_2,
        reg_target_out => reg_target_out_2,
        reg_dest_new   => reg_dest_new_2,
        intr_enable    => intr_enable_2);

	--Processo sensível a todos os ports e sinais  
	reg_proc: process(clk)
	begin
		--Atualiza  banco na borda de descida
		if falling_edge(clk) then
			reg_sel_bank_RT <= sel_bank_RT;
		end if;
	end process;
	
	--Multiplex dos sinais de entrada
	rs_index_1 <= rs_index_cpu when reg_sel_bank_RT = '0' 
				else rs_index_RT;
	rt_index_1 <= rt_index_cpu when reg_sel_bank_RT = '0' 
				else rt_index_RT;			
	rd_index_1 <= rd_index_cpu when reg_sel_bank_RT = '0' 
				else rd_index_RT;
   reg_dest_new_1 <= reg_dest_new_cpu when reg_sel_bank_RT = '0'
					 else reg_dest_new_RT;
	
	rs_index_2 <= rs_index_cpu when reg_sel_bank_RT = '1' 
				else rs_index_RT;
	rt_index_2 <= rt_index_cpu when reg_sel_bank_RT = '1' 
				else rt_index_RT;			
	rd_index_2 <= rd_index_cpu when reg_sel_bank_RT = '1' 
				else rd_index_RT;
   reg_dest_new_2 <= reg_dest_new_cpu when reg_sel_bank_RT = '1'
					 else reg_dest_new_RT;
   
	--Multiplex dos sinais de saída
	intr_enable_cpu <= intr_enable_1	when reg_sel_bank_RT = '0'
					  else intr_enable_2;
   reg_source_out_cpu <= reg_source_out_1	when reg_sel_bank_RT = '0'
						  else reg_source_out_2;
   reg_target_out_cpu <= reg_target_out_1	when reg_sel_bank_RT = '0'
						  else reg_target_out_2;
	
	intr_enable_RT <= intr_enable_1	when reg_sel_bank_RT = '1' 
					 else intr_enable_2;
   reg_source_out_RT <= reg_source_out_1	when reg_sel_bank_RT = '1'
						 else	reg_source_out_2;
   reg_target_out_RT <= reg_target_out_1	when reg_sel_bank_RT = '1'
						 else	reg_target_out_2;

end; --architecture ram_block_duplo_RT
