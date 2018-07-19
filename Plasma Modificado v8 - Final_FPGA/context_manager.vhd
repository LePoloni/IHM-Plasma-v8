---------------------------------------------------------------------
-- TITLE: Gerenciador de Contexto
-- AUTHOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATE CREATED: 25/11/16
-- FILENAME: context_manager.vhd
-- PROJECT: Plasma CPU Modificado v2
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Parte do Microkernel.
--		Faz o backup e restauração do contexto das tarefas na memória RAM_RT.
-- MODELO DO TCB:
--		Address
--		3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
--		1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
--		Value          |               |               |
--		0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 t t t t t x r r r r r 0 0
--		Legend
--		t - número da tarefa
--		r - registrador salvo
--    x - (0) faixa de registradores, (1) faixa para outros parâmetros

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- MOVIFICADO:
-- 01/12/16 - Limpei os sinais desnecessários e inclui novo sinal (PC)
-- 07/12/16 - Criado mais dois estados nas máquinas de estados para aguardar
--				  a confirmação da conclusão da restauração ou backup do PC
--				  Os bits de sinalização de backup_ready e restore_ready estavam
--				  errados, bit 7 ao invés de bit 8
-- xx/xx/16 - xxxx
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;
use ieee.numeric_std.all;		--Novidade
use IEEE.STD_LOGIC_ARITH.ALL;

entity context_manager is
	port(	clk          			: in std_logic;									--ok
			reset			     		: in std_logic;									--ok

			--Microkernel conectado ao bloco reg_bank_duplo
			rs_index_RT       	: out  std_logic_vector(5 downto 0);		--ok End. fonte de dados (6 bits ao invés de 5)
			rt_index_RT       	: out  std_logic_vector(5 downto 0);		--x End. fonte de ou destino de dados (fixo em 0)
			rd_index_RT       	: out  std_logic_vector(5 downto 0);		--okEnd. destino de dados
			reg_source_out_RT 	: in 	 std_logic_vector(31 downto 0);		--ok Saída de dados de acordo com rs
			reg_target_out_RT 	: in   std_logic_vector(31 downto 0);		--x Saída de dados de acordo com rt
			reg_dest_new_RT   	: out  std_logic_vector(31 downto 0);		--ok Entrada de dados de acordo com rd
		  
			--Microkernel conectado ao bloco ram_rt
			mk_address    		: out	std_logic_vector(31 downto 0);		--ok Microkernel - endereço da memória RAM TCB
			mk_byte_we    		: out std_logic_vector(3 downto 0);			--ok Microkernel - bytes para escrita na memória RAM TCB
			mk_data_w     		: out std_logic_vector(31 downto 0);		--ok Microkernel - dado para escrita na RAM TCB
			mk_data_r     		: in	std_logic_vector(31 downto 0);		--ok Microkernel - dado para leitura na RAM TCB
			
			--Microkernel sinais internos
			task_futura				: in integer range 0 to 31;					--ok Número da tarefa futura
			task_antiga				: in integer range 0 to 31;					--ok Número da tarefa antiga
			backup_init				: in std_logic;									--ok Solicitação de início de backup
			backup_ready	   	: out std_logic;									--ok Sinalização de backup de registradores pronto
			pc_backup				: in std_logic_vector(31 downto 0);			--ok Valor de PC para backup
			restore_init			: in std_logic;									--ok Solicitação de início de restauração
			restore_ready			: out std_logic;									--ok Sinalização de restauração de regs. pronto
			pc_restore				: out std_logic_vector(31 downto 0);			--ok Valor de PC restaurado
			
			--Saída para depuração (criado em 24/11/16)
			--mk_debug					: out std_logic_vector(7 downto 0)			
			--q		  					: out integer range 0 to 32
			output_restoreX				: out std_logic_vector(8 downto 0);
			output_backupX					: out std_logic_vector(8 downto 0)
		);
end; --entity context_manager

architecture logic of context_manager is
	--Constantes (não estão em uso no momento)
	constant TCP_SIZE       : integer := 64;			--Tamanho do TCP em words
	constant TCP_REGS			: integer := 0;			--Offset dos registradores dentro do TCP em words
	
	--Sinais (atualizadar apenas no final dos processos)
	signal ram_backup			: std_logic_vector(31 downto 8);
	signal ram_restore		: std_logic_vector(31 downto 8);

	--Máquina de estados
	signal input_backup, input_restore 		: std_logic;
	signal output_backup, output_restore 	: std_logic_vector(8 downto 0);	--8-done 7-pc 6-w_mem 5-r_bank 4~0-address
	signal read_add : std_logic_vector(4 downto 0);

	-- Build an enumerated type for the state machine
	type state_type is (s0, s1, s2, s3, s4, s5, s6, s7, s8, s9,
								s10, s11, s12, s13, s14, s15, s16, s17, s18, s19,
								s20, s21, s22, s23, s24, s25, s26, s27, s28, s29,
								s30, s31, s32, s33, s34, s35, s36);
								
	-- Build an enumerated type for the state machine
	type state_type2 is (s0, s1, s2, s3, s4, s5, s6, s7, s8, s9,
								s10, s11, s12, s13, s14, s15, s16, s17, s18, s19,
								s20, s21, s22, s23, s24, s25, s26, s27, s28, s29,
								s30, s31, s32, s33, s34, s35, s36, s37, s38, s39,
								s40, s41, s42, s43, s44, s45, s46, s47, s48, s49,
								s50, s51, s52, s53, s54, s55, s56, s57, s58, s59,
								s60, s61, s62, s63, s64, s65, s66, s67);

	-- Register to hold the current state
	signal state_backup	  : state_type;
	signal state_restore   : state_type2;
	
	--Sinal de clock diferenciado para o tipo de opração
	signal clkx : std_logic;

	
begin  --architecture
	-- Saída não utilizada
	rt_index_RT <= ZERO(5 downto 0);
	--																			 tarefa registrador (considenando os bits 1 e 0)
	--Calcula o endereço da memória RAM_RT (24 msbs) -> 0x0002(00~1F)(00~FC)
	ram_backup	<= ZERO(31 downto 18) & "10000" & conv_std_logic_vector(task_antiga,5);
	ram_restore	<= ZERO(31 downto 18) & "10000" & conv_std_logic_vector(task_futura,5);
--Teste 12/13/16 Verificação do restore !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1111
--	ram_backup	<= ZERO(31 downto 18) & "10000" & conv_std_logic_vector(0,5);
--	ram_restore	<= ZERO(31 downto 18) & "10000" & conv_std_logic_vector(1,5);
	--Talves registrar esses valores apenas no começo da máquina de estado!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--BACKUP DE TAREFA - OK
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	
	input_backup <= backup_init;
	backup_ready <= output_backup(8);
	
	output_backupX <= output_backup;
	output_restoreX <= output_restore;

	-- Logic to advance to the next state
	process (clk, reset)
	begin
		if reset = '1' then
			state_backup <= s0;
		elsif (rising_edge(clk)) then
			case state_backup is
				when s0=>
					if input_backup = '1' then
						state_backup <= s1;
					else
						state_backup <= s0;
					end if;
				when s1=>
					if input_backup = '1' then
						state_backup <= s2;
					else
						state_backup <= s0;
					end if;
				when s2=>
					if input_backup = '1' then
						state_backup <= s3;
					else
						state_backup <= s0;
					end if;
				when s3 =>
					if input_backup = '1' then
						state_backup <= s4;
					else
						state_backup <= s0;
					end if;
				when s4=>
					if input_backup = '1' then
						state_backup <= s5;
					else
						state_backup <= s0;
					end if;
				when s5=>
					if input_backup = '1' then
						state_backup <= s6;
					else
						state_backup <= s0;
					end if;
				when s6=>
					if input_backup = '1' then
						state_backup <= s7;
					else
						state_backup <= s0;
					end if;
				when s7=>
					if input_backup = '1' then
						state_backup <= s8;
					else
						state_backup <= s0;
					end if;
				when s8=>
					if input_backup = '1' then
						state_backup <= s9;
					else
						state_backup <= s0;
					end if;
				when s9=>
					if input_backup = '1' then
						state_backup <= s10;
					else
						state_backup <= s0;
					end if;
				when s10=>
					if input_backup = '1' then
						state_backup <= s11;
					else
						state_backup <= s0;
					end if;
				when s11=>
					if input_backup = '1' then
						state_backup <= s12;
					else
						state_backup <= s0;
					end if;
				when s12=>
					if input_backup = '1' then
						state_backup <= s13;
					else
						state_backup <= s0;
					end if;
				when s13=>
					if input_backup = '1' then
						state_backup <= s14;
					else
						state_backup <= s0;
					end if;
				when s14=>
					if input_backup = '1' then
						state_backup <= s15;
					else
						state_backup <= s0;
					end if;
				when s15=>
					if input_backup = '1' then
						state_backup <= s16;
					else
						state_backup <= s0;
					end if;
				when s16=>
					if input_backup = '1' then
						state_backup <= s17;
					else
						state_backup <= s0;
					end if;
				when s17=>
					if input_backup = '1' then
						state_backup <= s18;
					else
						state_backup <= s0;
					end if;
				when s18=>
					if input_backup = '1' then
						state_backup <= s19;
					else
						state_backup <= s0;
					end if;
				when s19=>
					if input_backup = '1' then
						state_backup <= s20;
					else
						state_backup <= s0;
					end if;
				when s20=>
					if input_backup = '1' then
						state_backup <= s21;
					else
						state_backup <= s0;
					end if;
				when s21=>
					if input_backup = '1' then
						state_backup <= s22;
					else
						state_backup <= s0;
					end if;
				when s22=>
					if input_backup = '1' then
						state_backup <= s23;
					else
						state_backup <= s0;
					end if;
				when s23=>
					if input_backup = '1' then
						state_backup <= s24;
					else
						state_backup <= s0;
					end if;
				when s24=>
					if input_backup = '1' then
						state_backup <= s25;
					else
						state_backup <= s0;
					end if;
				when s25=>
					if input_backup = '1' then
						state_backup <= s26;
					else
						state_backup <= s0;
					end if;
				when s26=>
					if input_backup = '1' then
						state_backup <= s27;
					else
						state_backup <= s0;
					end if;
				when s27=>
					if input_backup = '1' then
						state_backup <= s28;
					else
						state_backup <= s0;
					end if;
				when s28=>
					if input_backup = '1' then
						state_backup <= s29;
					else
						state_backup <= s0;
					end if;
				when s29=>
					if input_backup = '1' then
						state_backup <= s30;
					else
						state_backup <= s0;
					end if;
				when s30=>
					if input_backup = '1' then
						state_backup <= s31;
					else
						state_backup <= s0;
					end if;
				when s31=>
					if input_backup = '1' then
						state_backup <= s32;
					else
						state_backup <= s0;
					end if;
				when s32=>
					if input_backup = '1' then
						state_backup <= s33;
					else
						state_backup <= s0;
					end if;
				when s33=>
					if input_backup = '1' then
						state_backup <= s34;
					else
						state_backup <= s0;
					end if;
				when s34=>
					if input_backup = '1' then
						state_backup <= s35;
					else
						state_backup <= s0;
					end if;
				when s35=>
					if input_backup = '1' then
						state_backup <= s36;
					else
						state_backup <= s0;
					end if;
				when s36=>
					if input_backup = '1' then
						state_backup <= s36;
					else
						state_backup <= s0;		--Aguarda o sinal backup_init ir para 0
					end if;				
			end case;
		end if;
	end process;

	-- Output depends solely on the current state
	process (state_backup)
	begin
		case state_backup is				 --8-done 7-pc 6-w_mem 5-r_bank 4~0-address
												 --dpwraaaaa
			when s0 =>	output_backup <= "000000000";
			when s1 =>	output_backup <= "000100001";	--RD end 1 - WR end x
			when s2 =>	output_backup <= "001100010";	--RD end 2 - WR end 1
			when s3 =>	output_backup <= "001100011";	--RD end 3 - WR end 2
			when s4 =>	output_backup <= "001100100";	--RD end 4 - WR end 3
			when s5 =>	output_backup <= "001100101";	--RD end 5 - WR end 4
			when s6 =>	output_backup <= "001100110";	--RD end 6 - WR end 5
			when s7 =>	output_backup <= "001100111";	--RD end 7 - WR end 6
			
			when s8 =>	output_backup <= "001101000";	--RD end 8 - WR end 7
			when s9 =>	output_backup <= "001101001";	--RD end 9 - WR end 8
			when s10 =>	output_backup <= "001101010";	--RD end 10 - WR end 9
			when s11 =>	output_backup <= "001101011";	--RD end 11 - WR end 10
			when s12 =>	output_backup <= "001101100";	--RD end 12 - WR end 11
			when s13 =>	output_backup <= "001101101";	--RD end 13 - WR end 12
			when s14 =>	output_backup <= "001101110";	--RD end 14 - WR end 13
			when s15 =>	output_backup <= "001101111";	--RD end 15 - WR end 14
			
			when s16 =>	output_backup <= "001110000";	--RD end 16 - WR end 15
			when s17 =>	output_backup <= "001110001";	--RD end 17 - WR end 16
			when s18 =>	output_backup <= "001110010";	--RD end 18 - WR end 17
			when s19 =>	output_backup <= "001110011";	--RD end 19 - WR end 18
			when s20 =>	output_backup <= "001110100";	--RD end 20 - WR end 19
			when s21 =>	output_backup <= "001110101";	--RD end 21 - WR end 20
			when s22 =>	output_backup <= "001110110";	--RD end 22 - WR end 21
			when s23 =>	output_backup <= "001110111";	--RD end 23 - WR end 22
			
			when s24 =>	output_backup <= "001111000";	--RD end 24 - WR end 23
			when s25 =>	output_backup <= "001111001";	--RD end 25 - WR end 24
			when s26 =>	output_backup <= "001111010";	--RD end 26 - WR end 25
			when s27 =>	output_backup <= "001111011";	--RD end 27 - WR end 26
			when s28 =>	output_backup <= "001111100";	--RD end 28 - WR end 27
			when s29 =>	output_backup <= "001111101";	--RD end 29 - WR end 28
			when s30 =>	output_backup <= "001111110";	--RD end 30 - WR end 29
			when s31 =>	output_backup <= "001111111";	--RD end 31 - WR end 30
			
			when s32 =>	output_backup <= "001000000";	--RD end x - WR end 31
			when s33 =>	output_backup <= "010000000";	--RD end x - WR end 0 PC
			when s34 =>	output_backup <= "000000000";	--Apenas aguarda backup do PC ser concluido
			when s35 =>	output_backup <= "000000000"; --Apenas aguarda backup do PC ser concluido	
			when s36 =>	output_backup <= "100000000";	--RD end x - WR end x
			
		end case;
	end process;

	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--RESTAURAÇÃO DE TAREFA - OK
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	
	input_restore <= restore_init;
	restore_ready <= output_restore(8);

	-- Logic to advance to the next state
	process (clk, reset)
	begin
		if reset = '1' then
			state_restore <= s0;
		elsif (rising_edge(clk)) then
			case state_restore is
				when s0=>
					if input_restore = '1' then
						state_restore <= s1;
					else
						state_restore <= s0;
					end if;
				when s1=>
					if input_restore = '1' then
						state_restore <= s2;
					else
						state_restore <= s0;
					end if;
				when s2=>
					if input_restore = '1' then
						state_restore <= s3;
					else
						state_restore <= s0;
					end if;
				when s3 =>
					if input_restore = '1' then
						state_restore <= s4;
					else
						state_restore <= s0;
					end if;
				when s4=>
					if input_restore = '1' then
						state_restore <= s5;
					else
						state_restore <= s0;
					end if;
				when s5=>
					if input_restore = '1' then
						state_restore <= s6;
					else
						state_restore <= s0;
					end if;
				when s6=>
					if input_restore = '1' then
						state_restore <= s7;
					else
						state_restore <= s0;
					end if;
				when s7=>
					if input_restore = '1' then
						state_restore <= s8;
					else
						state_restore <= s0;
					end if;
				when s8=>
					if input_restore = '1' then
						state_restore <= s9;
					else
						state_restore <= s0;
					end if;
				when s9=>
					if input_restore = '1' then
						state_restore <= s10;
					else
						state_restore <= s0;
					end if;
				when s10=>
					if input_restore = '1' then
						state_restore <= s11;
					else
						state_restore <= s0;
					end if;
				when s11=>
					if input_restore = '1' then
						state_restore <= s12;
					else
						state_restore <= s0;
					end if;
				when s12=>
					if input_restore = '1' then
						state_restore <= s13;
					else
						state_restore <= s0;
					end if;
				when s13=>
					if input_restore = '1' then
						state_restore <= s14;
					else
						state_restore <= s0;
					end if;
				when s14=>
					if input_restore = '1' then
						state_restore <= s15;
					else
						state_restore <= s0;
					end if;
				when s15=>
					if input_restore = '1' then
						state_restore <= s16;
					else
						state_restore <= s0;
					end if;
				when s16=>
					if input_restore = '1' then
						state_restore <= s17;
					else
						state_restore <= s0;
					end if;
				when s17=>
					if input_restore = '1' then
						state_restore <= s18;
					else
						state_restore <= s0;
					end if;
				when s18=>
					if input_restore = '1' then
						state_restore <= s19;
					else
						state_restore <= s0;
					end if;
				when s19=>
					if input_restore = '1' then
						state_restore <= s20;
					else
						state_restore <= s0;
					end if;
				when s20=>
					if input_restore = '1' then
						state_restore <= s21;
					else
						state_restore <= s0;
					end if;
				when s21=>
					if input_restore = '1' then
						state_restore <= s22;
					else
						state_restore <= s0;
					end if;
				when s22=>
					if input_restore = '1' then
						state_restore <= s23;
					else
						state_restore <= s0;
					end if;
				when s23=>
					if input_restore = '1' then
						state_restore <= s24;
					else
						state_restore <= s0;
					end if;
				when s24=>
					if input_restore = '1' then
						state_restore <= s25;
					else
						state_restore <= s0;
					end if;
				when s25=>
					if input_restore = '1' then
						state_restore <= s26;
					else
						state_restore <= s0;
					end if;
				when s26=>
					if input_restore = '1' then
						state_restore <= s27;
					else
						state_restore <= s0;
					end if;
				when s27=>
					if input_restore = '1' then
						state_restore <= s28;
					else
						state_restore <= s0;
					end if;
				when s28=>
					if input_restore = '1' then
						state_restore <= s29;
					else
						state_restore <= s0;
					end if;
				when s29=>
					if input_restore = '1' then
						state_restore <= s30;
					else
						state_restore <= s0;
					end if;
				when s30=>
					if input_restore = '1' then
						state_restore <= s31;
					else
						state_restore <= s0;
					end if;
				when s31=>
					if input_restore = '1' then
						state_restore <= s32;
					else
						state_restore <= s0;
					end if;
				when s32=>
					if input_restore = '1' then
						state_restore <= s33;
					else
						state_restore <= s0;
					end if;
				when s33=>
					if input_restore = '1' then
						state_restore <= s34;
					else
						state_restore <= s0;
					end if;
				when s34=>
					if input_restore = '1' then
						state_restore <= s35;
					else
						state_restore <= s0;
					end if;
				when s35=>
					if input_restore = '1' then
						state_restore <= s36;
					else
						state_restore <= s0;
					end if;
--				when s36=>
--					if input_restore = '1' then
--						state_restore <= s36;
--					else
--						state_restore <= s0;		--Aguarda o sinal restore_init ir para 0
--					end if;
				--Ajuste
				when s36=>
					if input_restore = '1' then
						state_restore <= s37;
					else
						state_restore <= s0;
					end if;
				when s37=>
					if input_restore = '1' then
						state_restore <= s38;
					else
						state_restore <= s0;
					end if;
				when s38=>
					if input_restore = '1' then
						state_restore <= s39;
					else
						state_restore <= s0;
					end if;
				when s39=>
					if input_restore = '1' then
						state_restore <= s40;
					else
						state_restore <= s0;
					end if;
				when s40=>
					if input_restore = '1' then
						state_restore <= s41;
					else
						state_restore <= s0;
					end if;
				when s41=>
					if input_restore = '1' then
						state_restore <= s42;
					else
						state_restore <= s0;
					end if;
				when s42=>
					if input_restore = '1' then
						state_restore <= s43;
					else
						state_restore <= s0;
					end if;
				when s43=>
					if input_restore = '1' then
						state_restore <= s44;
					else
						state_restore <= s0;
					end if;
				when s44=>
					if input_restore = '1' then
						state_restore <= s45;
					else
						state_restore <= s0;
					end if;
				when s45=>
					if input_restore = '1' then
						state_restore <= s46;
					else
						state_restore <= s0;
					end if;
				when s46=>
					if input_restore = '1' then
						state_restore <= s47;
					else
						state_restore <= s0;
					end if;
				when s47=>
					if input_restore = '1' then
						state_restore <= s48;
					else
						state_restore <= s0;
					end if;
				when s48=>
					if input_restore = '1' then
						state_restore <= s49;
					else
						state_restore <= s0;
					end if;
				when s49=>
					if input_restore = '1' then
						state_restore <= s50;
					else
						state_restore <= s0;
					end if;
				when s50=>
					if input_restore = '1' then
						state_restore <= s51;
					else
						state_restore <= s0;
					end if;
				when s51=>
					if input_restore = '1' then
						state_restore <= s52;
					else
						state_restore <= s0;
					end if;
				when s52=>
					if input_restore = '1' then
						state_restore <= s53;
					else
						state_restore <= s0;
					end if;
				when s53=>
					if input_restore = '1' then
						state_restore <= s54;
					else
						state_restore <= s0;
					end if;
				when s54=>
					if input_restore = '1' then
						state_restore <= s55;
					else
						state_restore <= s0;
					end if;
				when s55=>
					if input_restore = '1' then
						state_restore <= s56;
					else
						state_restore <= s0;
					end if;
				when s56=>
					if input_restore = '1' then
						state_restore <= s57;
					else
						state_restore <= s0;
					end if;
				when s57=>
					if input_restore = '1' then
						state_restore <= s58;
					else
						state_restore <= s0;
					end if;
				when s58=>
					if input_restore = '1' then
						state_restore <= s59;
					else
						state_restore <= s0;
					end if;
				when s59=>
					if input_restore = '1' then
						state_restore <= s60;
					else
						state_restore <= s0;
					end if;
				when s60=>
					if input_restore = '1' then
						state_restore <= s61;
					else
						state_restore <= s0;
					end if;
				when s61=>
					if input_restore = '1' then
						state_restore <= s62;
					else
						state_restore <= s0;
					end if;
				when s62=>
					if input_restore = '1' then
						state_restore <= s63;
					else
						state_restore <= s0;
					end if;
				when s63=>
					if input_restore = '1' then
						state_restore <= s64;
					else
						state_restore <= s0;
					end if;
				when s64=>
					if input_restore = '1' then
						state_restore <= s65;
					else
						state_restore <= s0;
					end if;
				when s65=>
					if input_restore = '1' then
						state_restore <= s66;
					else
						state_restore <= s0;
					end if;
				when s66=>
					if input_restore = '1' then
						state_restore <= s67;
					else
						state_restore <= s0;
					end if;	
				when s67=>
					if input_restore = '1' then
						state_restore <= s67;
					else
						state_restore <= s0;		--Aguarda o sinal restore_init ir para 0
					end if;
			end case;
		end if;
	end process;

	-- Output depends solely on the current state
	process (state_restore)
	begin
		case state_restore is			  --8-done 7-pc 6-w_reg 5-r_mem 4~0-address
												  --dpwraaaaa
--			when s0 =>	output_restore <= "000000000";
--			when s1 =>	output_restore <= "000100001";	--RD end 1 - WR end x
--			when s2 =>	output_restore <= "001100010";	--RD end 2 - WR end 1
--			when s3 =>	output_restore <= "001100011";	--RD end 3 - WR end 2
--			when s4 =>	output_restore <= "001100100";	--RD end 4 - WR end 3
--			when s5 =>	output_restore <= "001100101";	--RD end 5 - WR end 4
--			when s6 =>	output_restore <= "001100110";	--RD end 6 - WR end 5
--			when s7 =>	output_restore <= "001100111";	--RD end 7 - WR end 6
--			
--			when s8 =>	output_restore <= "001101000";	--RD end 8 - WR end 7
--			when s9 =>	output_restore <= "001101001";	--RD end 9 - WR end 8
--			when s10 =>	output_restore <= "001101010";	--RD end 10 - WR end 9
--			when s11 =>	output_restore <= "001101011";	--RD end 11 - WR end 10
--			when s12 =>	output_restore <= "001101100";	--RD end 12 - WR end 11
--			when s13 =>	output_restore <= "001101101";	--RD end 13 - WR end 12
--			when s14 =>	output_restore <= "001101110";	--RD end 14 - WR end 13
--			when s15 =>	output_restore <= "001101111";	--RD end 15 - WR end 14
--			
--			when s16 =>	output_restore <= "001110000";	--RD end 16 - WR end 15
--			when s17 =>	output_restore <= "001110001";	--RD end 17 - WR end 16
--			when s18 =>	output_restore <= "001110010";	--RD end 18 - WR end 17
--			when s19 =>	output_restore <= "001110011";	--RD end 19 - WR end 18
--			when s20 =>	output_restore <= "001110100";	--RD end 20 - WR end 19
--			when s21 =>	output_restore <= "001110101";	--RD end 21 - WR end 20
--			when s22 =>	output_restore <= "001110110";	--RD end 22 - WR end 21
--			when s23 =>	output_restore <= "001110111";	--RD end 23 - WR end 22
----Teste com leitura dupla dos registradores t0..t4
----			when s8 =>	output_restore <= "001101000";	--RD end 8 - WR end 7
----			when s9 =>	output_restore <= "001101000";	--RD end 9 - WR end 8
----			when s10 =>	output_restore <= "000101001";	--RD end 10 - WR end 9
----			when s11 =>	output_restore <= "001111001";	--RD end 11 - WR end 10
----			when s12 =>	output_restore <= "000101010";	--RD end 12 - WR end 11
----			when s13 =>	output_restore <= "001101010";	--RD end 13 - WR end 12
----			when s14 =>	output_restore <= "000101011";	--RD end 14 - WR end 13
----			when s15 =>	output_restore <= "001101011";	--RD end 15 - WR end 14
----			
----			when s16 =>	output_restore <= "000101100";	--RD end 16 - WR end 15
----			when s17 =>	output_restore <= "001101100";	--RD end 17 - WR end 16
----			when s18 =>	output_restore <= "000101101";	--RD end 18 - WR end 17
----			when s19 =>	output_restore <= "001101101";	--RD end 19 - WR end 18
----			when s20 =>	output_restore <= "000110100";	--RD end 20 - WR end 19
----			when s21 =>	output_restore <= "001110101";	--RD end 21 - WR end 20
----			when s22 =>	output_restore <= "001110110";	--RD end 22 - WR end 21
----			when s23 =>	output_restore <= "001110111";	--RD end 23 - WR end 22
--			
--			when s24 =>	output_restore <= "001111000";	--RD end 24 - WR end 23
--			when s25 =>	output_restore <= "001111001";	--RD end 25 - WR end 24
--			when s26 =>	output_restore <= "001111010";	--RD end 26 - WR end 25
--			when s27 =>	output_restore <= "001111011";	--RD end 27 - WR end 26
--			when s28 =>	output_restore <= "001111100";	--RD end 28 - WR end 27
--			when s29 =>	output_restore <= "001111101";	--RD end 29 - WR end 28
--			when s30 =>	output_restore <= "001111110";	--RD end 30 - WR end 29
--			when s31 =>	output_restore <= "001111111";	--RD end 31 - WR end 30
--			
----			when s32 =>	output_restore <= "001100000";	--RD end 0 - WR end 31
--			--Teste leitura e gravação simultânea
--			when s32 =>	output_restore <= "010100000";	--RD end 0 - WR end 31
----			when s33 =>	output_restore <= "010000000";	--RD end x - WR PC
--			when s33 =>	output_restore <= "000000000";	--RD end x - WR PC
--			when s34 =>	output_restore <= "000000000";	--Apenas aguarda restore do PC ser concluido
--			when s35 =>	output_restore <= "000000000"; 	--Apenas aguarda restore do PC ser concluido			
--			when s36 =>	output_restore <= "100000000";	--RD end x - WR end x

			when s0 =>	output_restore <= "000000000";
			
			when s1 =>	output_restore <= "000100001";	--RD end 1 - WR end x
			when s2 =>	output_restore <= "001100001";	--RD end 1 - WR end 1
			when s3 =>	output_restore <= "000100010";	--RD end 2 - WR end x
			when s4 =>	output_restore <= "001100010";	--RD end 2 - WR end 2
			when s5 =>	output_restore <= "001100011";	--RD end 3 - WR end x
			when s6 =>	output_restore <= "001100011";	--RD end 3 - WR end 3
			when s7 =>	output_restore <= "001100100";	--RD end 4 - WR end x
			when s8 =>	output_restore <= "001100100";	--RD end 4 - WR end 4
			
			when s9 =>	output_restore <= "001100101";	--RD end 5 - WR end x
			when s10 =>	output_restore <= "001100101";	--RD end 5 - WR end 5
			when s11 =>	output_restore <= "001100110";	--RD end 6 - WR end x
			when s12 =>	output_restore <= "001100110";	--RD end 6 - WR end 6
			when s13 =>	output_restore <= "001100111";	--RD end 7 - WR end x
			when s14 =>	output_restore <= "001100111";	--RD end 7 - WR end 7
			when s15 =>	output_restore <= "000101000";	--RD end 8 - WR end x
			when s16 =>	output_restore <= "001001000";	--RD end 8 - WR end 8 Só WR
			
			when s17 =>	output_restore <= "000101001";	--RD end 9 - WR end x
			when s18 =>	output_restore <= "001001001";	--RD end 9 - WR end 9 Só WR
			when s19 =>	output_restore <= "000101010";	--RD end 10 - WR end x
			when s20 =>	output_restore <= "001001010";	--RD end 10 - WR end 10 Só WR
			when s21 =>	output_restore <= "000101011";	--RD end 11 - WR end x
			when s22 =>	output_restore <= "001001011";	--RD end 11 - WR end 11 Só WR
			when s23 =>	output_restore <= "000101100";	--RD end 12 - WR end x
			when s24 =>	output_restore <= "001001100";	--RD end 12 - WR end 12 Só WR
			
			when s25 =>	output_restore <= "000101101";	--RD end 13 - WR end x
			when s26 =>	output_restore <= "001101101";	--RD end 13 - WR end 13
			when s27 =>	output_restore <= "000101110";	--RD end 14 - WR end x
			when s28 =>	output_restore <= "001101110";	--RD end 14 - WR end 14
			when s29 =>	output_restore <= "000101111";	--RD end 15 - WR end x
			when s30 =>	output_restore <= "001101111";	--RD end 15 - WR end 15
			when s31 =>	output_restore <= "000110000";	--RD end 16 - WR end x
			when s32 =>	output_restore <= "001110000";	--RD end 16 - WR end 16
			
			when s33 =>	output_restore <= "000110001";	--RD end 17 - WR end x
			when s34 =>	output_restore <= "001110001";	--RD end 17 - WR end 17
			when s35 =>	output_restore <= "000110010";	--RD end 18 - WR end x
			when s36 =>	output_restore <= "001110010";	--RD end 18 - WR end 18
			when s37 =>	output_restore <= "001110011";	--RD end 19 - WR end x
			when s38 =>	output_restore <= "001110011";	--RD end 19 - WR end 19
			when s39 =>	output_restore <= "001110100";	--RD end 20 - WR end x
			when s40 =>	output_restore <= "001110100";	--RD end 20 - WR end 20
			
			when s41 =>	output_restore <= "001110101";	--RD end 21 - WR end x
			when s42 =>	output_restore <= "001110101";	--RD end 21- WR end 21
			when s43 =>	output_restore <= "001110110";	--RD end 22 - WR end x
			when s44 =>	output_restore <= "001110110";	--RD end 22 - WR end 22
			when s45 =>	output_restore <= "001110111";	--RD end 23 - WR end x
			when s46 =>	output_restore <= "001110111";	--RD end 23 - WR end 23
			when s47 =>	output_restore <= "000111000";	--RD end 24 - WR end x
			when s48 =>	output_restore <= "001111000";	--RD end 24 - WR end 24
			
			when s49 =>	output_restore <= "000111001";	--RD end 25 - WR end x
			when s50 =>	output_restore <= "001111001";	--RD end 25 - WR end 25
			when s51 =>	output_restore <= "000111010";	--RD end 26 - WR end x
			when s52 =>	output_restore <= "001111010";	--RD end 26 - WR end 26
			when s53 =>	output_restore <= "000111011";	--RD end 27 - WR end x
			when s54 =>	output_restore <= "001111011";	--RD end 27 - WR end 27
			when s55 =>	output_restore <= "000111100";	--RD end 28 - WR end x
			when s56 =>	output_restore <= "001111100";	--RD end 28 - WR end 28
			
			when s57 =>	output_restore <= "000111101";	--RD end 29 - WR end x
			when s58 =>	output_restore <= "001111101";	--RD end 29 - WR end 29
			when s59 =>	output_restore <= "000111110";	--RD end 30 - WR end x
			when s60 =>	output_restore <= "001111110";	--RD end 30 - WR end 30
			when s61 =>	output_restore <= "000111111";	--RD end 31 - WR end x
			when s62 =>	output_restore <= "001111111";	--RD end 31 - WR end 31
			
						
			when s63 =>	output_restore <= "000100000";	--RD end 0 - WR end x
			when s64 =>	output_restore <= "010000000";	--RD end 0 - WR PC         Só WR!!!!!!!
			when s65 =>	output_restore <= "000000000";	--Apenas aguarda restore do PC ser concluido
			when s66 =>	output_restore <= "000000000"; 	--Apenas aguarda restore do PC ser concluido			
			when s67 =>	output_restore <= "100000000";	--RD end x - WR end x
			
		end case;
	end process;


	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	--BACK/RESTAURAÇÃO DE TAREFA
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	
--	process (clk, output_backup, output_restore)
--	begin
--		--Se ocorreu um clk
--		if rising_edge(clk) then
--			
--			--Se for um backup - OK
--			if backup_init = '1' then
--				--Se não está realizando leitura ou escrita
--				if output_backup(7 downto 5) = "000" then
--					rs_index_RT <= "000000";						--Seleciona endereço de $0
--					rd_index_RT <= "000000";						--Seleciona endereço de $0
--					mk_address <= ZERO(31 downto 0);				--Seleciona endereço 0 da memória
--					mk_byte_we  <= "0000";							--Desabilita gravação na memória
--				else
--					--Se read reg
--					if output_backup(5) = '1' then
--						--Seleciona o banco de registradores
--						rs_index_RT <= '0' & output_backup(4 downto 0);
--						read_add <= output_backup(4 downto 0);					--Atualizado apenas no final do processo
--					end if;
--		
--					--Se é write mem
--					if output_backup(6) = '1' then
--						--Seleciona a memória RAM_RT (vai ser escrito no próximo clock)
--						mk_address  <= ram_backup & '0' & read_add & "00";	--Grava no endereço memorizado anteriormente
--						mk_byte_we  <= "1111";
--						mk_data_w	<= reg_source_out_RT;						--Valor lido um clock atrás
----						mk_data_w	<= ZERO(31 downto 5) & read_add;	--TESTE usa o própio end. do reg com valor
--					
--					--Senão, se PC, salva o PC
--					elsif output_backup(7) = '1' then
--						mk_address  <= ram_backup & '0' & "0000000";			--PC no endereço 0 do TCB selecionado]
--						mk_byte_we  <= "1111";
--						mk_data_w	<= pc_backup;									--Valor de PC passado pelo microkernel
----						mk_data_w	<= zero(31 downto 8) & "11011100";	--TESTE
--					end if;
--				end if;
--			
--			--Senão, se for um restore
--			elsif restore_init = '1' then
--				--Se não está realizando leitura ou escrita
--				if output_restore(7 downto 5) = "000" then
--					rs_index_RT <= "000000";						--Seleciona endereço de $0
--					rd_index_RT <= "000000";						--Seleciona endereço de $0
--					mk_address <= ZERO(31 downto 0);				--Seleciona endereço 0 da memória
--					mk_byte_we  <= "0000";							--Desabilita gravação na memória
--				else
--					--Se read mem
--					if output_restore(5) = '1' then
--						--Seleciona a memória RAM_RT
--						mk_address  <= ram_restore & '0' & output_restore(4 downto 0) & "00";	--Grava no endereço memorizado anteriormente
--						mk_byte_we  <= "0000";
--						read_add <= output_restore(4 downto 0);					--Atualizado apenas no final do processo
--					end if;
--					
--					--Se é write reg
--					if output_restore(6) = '1' then
--						--Seleciona a o banco de registradores (vai ser escrito no próximo clock)
--						rd_index_RT <= '0' & read_add;
--						reg_dest_new_RT <= mk_data_r;
--					
--					--Senão, se PC, restaura o PC
--					elsif output_restore(7) ='1' then
--						pc_restore <= mk_data_r;									--PC no endereço 0 do TCB selecionado
----						pc_restore <= zero(31 downto 8) & "11011100";		--TESTE - End Task 1 Plasma_RT3.asm
--					end if;	
--				end if;
--			--Senão
--			else
--				rs_index_RT <= "000000";						--Seleciona endereço de $0
--				rd_index_RT <= "000000";						--Seleciona endereço de $0
--				mk_address <= ZERO(31 downto 0);				--Seleciona endereço 0 da memória
--				mk_byte_we  <= "0000";							--Desabilita gravação na memória		
--			end if;
--			
--		end if;
--	end process;

	--Para backup clk = 0, para restore clkx = /clk, defasa a leitura do pulso de escrita
	clkx <= not(clk) when restore_init = '1' else
			  clk;
			  
--	clkx <= clk;
	
	process (clkx, output_backup, output_restore, backup_init, restore_init)
	begin
		--Se ocorreu um clk
		if rising_edge(clkx) then
			
			--Se for um backup - OK
			if backup_init = '1' then
				--Se não está realizando leitura ou escrita
				if output_backup(7 downto 5) = "000" then
					rs_index_RT <= "000000";						--Seleciona endereço de $0
					rd_index_RT <= "000000";						--Seleciona endereço de $0
					mk_address <= ZERO(31 downto 0);				--Seleciona endereço 0 da memória
					mk_byte_we  <= "0000";							--Desabilita gravação na memória
				else
					--Se read reg
					if output_backup(5) = '1' then
						--Seleciona o banco de registradores
						rs_index_RT <= '0' & output_backup(4 downto 0);
						read_add <= output_backup(4 downto 0);					--Atualizado apenas no final do processo
					end if;
		
					--Se é write mem
					if output_backup(6) = '1' then
						--Seleciona a memória RAM_RT (vai ser escrito no próximo clock)
						mk_address  <= ram_backup & '0' & read_add & "00";	--Grava no endereço memorizado anteriormente
						mk_byte_we  <= "1111";
						mk_data_w	<= reg_source_out_RT;						--Valor lido um clock atrás
--						mk_data_w	<= ZERO(31 downto 5) & read_add;	--TESTE usa o própio end. do reg com valor
					
					--Senão, se PC, salva o PC
					elsif output_backup(7) = '1' then
						mk_address  <= ram_backup & '0' & "0000000";			--PC no endereço 0 do TCB selecionado]
						mk_byte_we  <= "1111";
						mk_data_w	<= pc_backup;									--Valor de PC passado pelo microkernel
--						mk_data_w	<= zero(31 downto 8) & "11011100";	--TESTE
					end if;
				end if;
			
			--Senão, se for um restore
			elsif restore_init = '1' then
				--Se não está realizando leitura ou escrita
				if output_restore(7 downto 5) = "000" then
					rs_index_RT <= "000000";						--Seleciona endereço de $0
					rd_index_RT <= "000000";						--Seleciona endereço de $0
					mk_address <= ZERO(31 downto 0);				--Seleciona endereço 0 da memória
					mk_byte_we  <= "0000";							--Desabilita gravação na memória
				else
					--Se read mem
					if output_restore(5) = '1' then
						--Seleciona a memória RAM_RT
						mk_address  <= ram_restore & '0' & output_restore(4 downto 0) & "00";	--Grava no endereço memorizado anteriormente
						mk_byte_we  <= "0000";
						read_add <= output_restore(4 downto 0);					--Atualizado apenas no final do processo
					end if;
					
					--Se é write reg
					if output_restore(6) = '1' then
						--Seleciona a o banco de registradores (vai ser escrito no próximo clock)
						rd_index_RT <= '0' & read_add;
						--Teste leitura e gravação simultânea
--						rd_index_RT <= '0' & output_restore(4 downto 0);
						reg_dest_new_RT <= mk_data_r;
					
					--Senão, se PC, restaura o PC
					elsif output_restore(7) ='1' then
						pc_restore <= mk_data_r;									--PC no endereço 0 do TCB selecionado
--						pc_restore <= zero(31 downto 8) & "11011100";		--TESTE - End Task 1 Plasma_RT3.asm
					end if;	
				end if;
			--Senão
			else
				rs_index_RT <= "000000";						--Seleciona endereço de $0
				rd_index_RT <= "000000";						--Seleciona endereço de $0
				mk_address <= ZERO(31 downto 0);				--Seleciona endereço 0 da memória
				mk_byte_we  <= "0000";							--Desabilita gravação na memória		
			end if;
			
		end if;
	end process;
	
	--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

--	--Apenas para validação da síntese
--	process (clk)
--		variable   cnt		   : integer range 0 to 32;
--	begin
--		if (rising_edge(clk)) then
--
--			if reset = '1' then
--				-- Reset the counter to 0
--				cnt := 0;
--
--			else
--				-- Increment the counter if counting is enabled			   
--				cnt := cnt + 1;
--
--			end if;
--		end if;
--
--		-- Output the current count
--		q <= cnt;
--	end process;



end; --architecture logic