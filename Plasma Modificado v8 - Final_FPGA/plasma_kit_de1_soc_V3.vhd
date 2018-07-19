---------------------------------------------------------------------
-- TÍTULO: Plasma Kit DE1-SoC
-- AUTOR: Leandro Poloni Dantas (leandro.poloni@gmail.com)
-- DATA DE CRIAÇÃO: 18/7/16
-- FILENAME: plasma_kit_de1_soc.vhd
-- PROJETO: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    This entity combines the CPU core with memory and a UART.
--		Ajuste para o kit DE1-SoC da Terasic
-- MDIFICADO:
-- 24/11/16 - Incluido o sinal mk_debug no Microkernel
-- 08/12/16 - Criado clock de 2Hz quando a a chave KEY(3) é pressionada
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;

entity plasma_kit_de1_soc is
   port(
		--//////////// CLOCK //////////
		CLOCK_50: in std_logic;
		CLOCK2_50: in std_logic;
		CLOCK3_50: in std_logic;
		CLOCK4_50: in std_logic;

		--//////////// SEG7 //////////
		HEX0: out std_logic_vector(6 downto 0);
		HEX1: out std_logic_vector(6 downto 0);
		HEX2: out std_logic_vector(6 downto 0);
		HEX3: out std_logic_vector(6 downto 0);
		HEX4: out std_logic_vector(6 downto 0);
		HEX5: out std_logic_vector(6 downto 0);

		--//////////// KEY //////////
		KEY: in std_logic_vector(3 downto 0);

		--//////////// LED //////////
		LEDR: out std_logic_vector(9 downto 0);

		--//////////// SW //////////
		SW: in std_logic_vector(9 downto 0));
end entity;

architecture conexoes of plasma_kit_de1_soc is

	--Sinais para conexão do Plasma
	signal clk          : std_logic;
	signal reset        : std_logic;
	
	signal uart_write   : std_logic;
	signal uart_read    : std_logic;
	
	signal address      : std_logic_vector(31 downto 2);
	signal byte_we      : std_logic_vector(3 downto 0); 
	signal data_write   : std_logic_vector(31 downto 0);
	signal data_read    : std_logic_vector(31 downto 0);
	signal mem_pause_in : std_logic;
	signal no_ddr_start : std_logic;
	signal no_ddr_stop  : std_logic;
	  
	signal gpio0_out    : std_logic_vector(31 downto 0);
	signal gpioA_in     : std_logic_vector(31 downto 0);
	
	--Sinais para depuaração
	signal address_next_debug 		: std_logic_vector(31 downto 2);
	signal data_r_debug				: std_logic_vector(31 downto 0);
	signal ram_data_r_debug			: std_logic_vector(31 downto 0);
	signal task_switch_RT_debug	: std_logic;
	signal mk_debug					: std_logic_vector(7 downto 0);

	--Decoder para endereço
	signal Nibble0		  : std_logic_vector(6 downto 0);
	signal Nibble1		  : std_logic_vector(6 downto 0);
	signal Nibble2		  : std_logic_vector(6 downto 0);
	signal Nibble3		  : std_logic_vector(6 downto 0);
	signal Nibble4		  : std_logic_vector(6 downto 0);
	signal Nibble7		  : std_logic_vector(6 downto 0);	

begin

	--Instancia do componente
	plasma1: plasma_RT

   --generic(memory_type : string := "XILINX_16X"; --"DUAL_PORT_" "ALTERA_LPM";	--LEANDRO: Comentado
	generic map(	--memory_type => "DUAL_PORT_",	--LEANDRO: Criado
						memory_type => "ALTERA_LPM",	--LEANDRO: Criado
						log_file    => "UNUSED",		--colocar nome do arquivo para gerar um log
						ethernet    => '0',				--1 para criar uma porta ethernet
						use_cache   => '0')				--1 para criar um cache

	port	map(	clk,
					reset,

					uart_write,
					uart_read,

					address,
					byte_we,
					data_write,
					data_read,
					mem_pause_in,
					no_ddr_start,
					no_ddr_stop,
        
					gpio0_out,
					gpioA_in,
					
					address_next_debug,
					data_r_debug,
					ram_data_r_debug,
					task_switch_RT_debug,
					mk_debug
				);
					
--	--Divide 50 MHz clock by two
--   clk_div: process(KEY(0), CLOCK_50)
--   begin
--		--Se a chave está pressionada (lógica reversa) 
--      if KEY(0) = '0' then
--         clk <= '0';
--      elsif rising_edge(CLOCK_50) then
--         clk <= not clk;
--      end if;
--	end process; --clk_div

	--Divide 50 MHz clock by n
   clk_div: process(KEY(0), CLOCK_50)
		variable   cnt		   : integer range 0 to 50000000;	
   begin
		--Se a chave está pressionada (lógica reversa) 
      if KEY(0) = '0' then
         clk <= '0';
			-- Reset the counter to 0
			cnt := 0;
		elsif KEY(1) = '0' then
			clk <= clk;
      elsif rising_edge(CLOCK_50) then
			--Clock de 25Hz
			if KEY(2) = '0' then						
				if cnt = 500000 then
					cnt := 0;
					-- Output the current count
					clk <= not clk;
				else
					-- Increment the counter if counting is enabled			   
					cnt := cnt + 1; 
				end if;
			--Clock de 2Hz
			elsif KEY(3) = '0' then
				if cnt = 12500000 then
					cnt := 0;
					-- Output the current count
					clk <= not clk;
				else
					-- Increment the counter if counting is enabled			   
					cnt := cnt + 1; 
				end if;
			--Clock de 1Hz
			else	
				if cnt = 25000000 then
					cnt := 0;
					-- Output the current count
					clk <= not clk;
				else
					-- Increment the counter if counting is enabled			   
					cnt := cnt + 1; 
				end if;			
			end if;	
      end if;
	end process; --clk_div
	
	--Conexão de ports e sinais
	-- <-- Sentido do sinal
	--clk					<= CLOCK_50;
	reset       		<= not KEY(0);	--Lógica reversa

	--uart_write  		<= open;
	uart_read   		<= '1';

	--Configuração para gravação no kit
--	HEX0 					<= not address_next_debug(8 downto 2);
--	HEX1 					<= not address_next_debug(15 downto 9);
--	HEX2 					<= not address_next_debug(22 downto 16);
--	HEX3 					<= not address_next_debug(29 downto 23);
--	HEX4(1 downto 0)	<= not address_next_debug(31 downto 30);
--	HEX4(6 downto 2)	<= not zero(6 downto 2);
	HEX5(0)				<= not clk;
	HEX5(1)				<= not task_switch_RT_debug;
--	HEX5(6 downto 2)	<= not zero(6 downto 2);
	HEX5(5 downto 2)	<= not mk_debug(3 downto 0);
	HEX5(6)				<= not (mk_debug(5) or mk_debug(4));
	--Configuração para simulação
--	HEX0 					<= address_next_debug(8 downto 2);
--	HEX1 					<= address_next_debug(15 downto 9);
--	HEX2 					<= address_next_debug(22 downto 16);
--	HEX3 					<= address_next_debug(29 downto 23);
--	HEX4(1 downto 0)	<= address_next_debug(31 downto 30);
--	HEX4(6 downto 2)	<= zero(6 downto 2);
--	HEX5(0)				<= clk;
--	HEX5(6 downto 1)	<= zero(6 downto 1);
	
	--byte_we			<= open;
	--data_write  		<= open;
	data_read   		<= zero(31 downto 0);
	mem_pause_in 		<= '0';
	--no_ddr_start 	<= open;
	--no_ddr_stop  	<= open;
  
	LEDR(9 downto 0)	<= gpio0_out(9 downto 0);
	gpioA_in     		<= zero(31 downto 10) & SW(9 downto 0);
	
		--Decoder do endereço da instrução/registrador/dado acessado
	-- Decodificacor sequencial
	-- Entra número --> sai valor decodificado 
--   Nibble0 <= 	not "0111111" when address(3 downto 2) = "00" else	-- dado = 0
--					--not "0000110" when address(3 downto 2) = "00" else	-- dado = 1
--					--not "1011011" when address(3 downto 2) = "00" else	-- dado = 2
--					--not "1001111" when address(3 downto 2) = "00" else	-- dado = 3
--					not "1100110" when address(3 downto 2) = "01" else	-- dado = 4
--					--not "1101101" when address(3 downto 2) = "01" else	-- dado = 5
--					--not "1111101" when address(3 downto 2) = "01" else	-- dado = 6
--					--not "0000111" when address(3 downto 2) = "01" else	-- dado = 7
--					not "1111111" when address(3 downto 2) = "10" else	-- dado = 8
--					--not "1101111" when address(3 downto 2) = "10" else	-- dado = 9
--					--not "1110111" when address(3 downto 2) = "10"else	-- dado = 10
--					--not "1111100" when address(3 downto 2) = "10" else	-- dado = 11
--					not "0111001" when address(3 downto 2) = "11" else	-- dado = 12/0xC
--					--not "1011110" when address(3 downto 2) = "11" else	-- dado = 13
--					--not "1111001" when address(3 downto 2) = "11" else	-- dado = 14
--					--not "1110001" when address(3 downto 2) = "11" else	-- dado = 15
--					not "0000000";
--	
--	Nibble1 <= 	not "0111111" when address(7 downto 4) = "0000" else	-- dado = 0
--					not "0000110" when address(7 downto 4) = "0001" else	-- dado = 1
--					not "1011011" when address(7 downto 4) = "0010" else	-- dado = 2
--					not "1001111" when address(7 downto 4) = "0011" else	-- dado = 3
--					not "1100110" when address(7 downto 4) = "0100" else	-- dado = 4
--					not "1101101" when address(7 downto 4) = "0101" else	-- dado = 5
--					not "1111101" when address(7 downto 4) = "0110" else	-- dado = 6
--					not "0000111" when address(7 downto 4) = "0111" else	-- dado = 7
--					not "1111111" when address(7 downto 4) = "1000" else	-- dado = 8
--					not "1101111" when address(7 downto 4) = "1001" else	-- dado = 9
--					not "1110111" when address(7 downto 4) = "1010" else	-- dado = 10/0xA
--					not "1111100" when address(7 downto 4) = "1011" else	-- dado = 11/0xB
--					not "0111001" when address(7 downto 4) = "1100" else	-- dado = 12/0xC
--					not "1011110" when address(7 downto 4) = "1101" else	-- dado = 13/0xD
--					not "1111001" when address(7 downto 4) = "1110" else	-- dado = 14/0xE
--					not "1110001" when address(7 downto 4) = "1111" else	-- dado = 15/0xF
--					not "0000000";
--					
--	Nibble2 <= 	not "0111111" when address(11 downto 8) = "0000" else	-- dado = 0
--					not "0000110" when address(11 downto 8) = "0001" else	-- dado = 1
--					not "1011011" when address(11 downto 8) = "0010" else	-- dado = 2
--					not "1001111" when address(11 downto 8) = "0011" else	-- dado = 3
--					not "1100110" when address(11 downto 8) = "0100" else	-- dado = 4
--					not "1101101" when address(11 downto 8) = "0101" else	-- dado = 5
--					not "1111101" when address(11 downto 8) = "0110" else	-- dado = 6
--					not "0000111" when address(11 downto 8) = "0111" else	-- dado = 7
--					not "1111111" when address(11 downto 8) = "1000" else	-- dado = 8
--					not "1101111" when address(11 downto 8) = "1001" else	-- dado = 9
--					not "1110111" when address(11 downto 8) = "1010" else	-- dado = 10/0xA
--					not "1111100" when address(11 downto 8) = "1011" else	-- dado = 11/0xB
--					not "0111001" when address(11 downto 8) = "1100" else	-- dado = 12/0xC
--					not "1011110" when address(11 downto 8) = "1101" else	-- dado = 13/0xD
--					not "1111001" when address(11 downto 8) = "1110" else	-- dado = 14/0xE
--					not "1110001" when address(11 downto 8) = "1111" else	-- dado = 15/0xF
--					not "0000000";
--					
--	Nibble3 <= 	not "0111111" when address(15 downto 12) = "0000" else	-- dado = 0
--					not "0000110" when address(15 downto 12) = "0001" else	-- dado = 1
--					not "1011011" when address(15 downto 12) = "0010" else	-- dado = 2
--					not "1001111" when address(15 downto 12) = "0011" else	-- dado = 3
--					not "1100110" when address(15 downto 12) = "0100" else	-- dado = 4
--					not "1101101" when address(15 downto 12) = "0101" else	-- dado = 5
--					not "1111101" when address(15 downto 12) = "0110" else	-- dado = 6
--					not "0000111" when address(15 downto 12) = "0111" else	-- dado = 7
--					not "1111111" when address(15 downto 12) = "1000" else	-- dado = 8
--					not "1101111" when address(15 downto 12) = "1001" else	-- dado = 9
--					not "1110111" when address(15 downto 12) = "1010" else	-- dado = 10/0xA
--					not "1111100" when address(15 downto 12) = "1011" else	-- dado = 11/0xB
--					not "0111001" when address(15 downto 12) = "1100" else	-- dado = 12/0xC
--					not "1011110" when address(15 downto 12) = "1101" else	-- dado = 13/0xD
--					not "1111001" when address(15 downto 12) = "1110" else	-- dado = 14/0xE
--					not "1110001" when address(15 downto 12) = "1111" else	-- dado = 15/0xF
--					not "0000000";
--					
--	Nibble4 <= 	not "0111111" when address(19 downto 16) = "0000" else	-- dado = 0
--					not "0000110" when address(19 downto 16) = "0001" else	-- dado = 1
--					not "1011011" when address(19 downto 16) = "0010" else	-- dado = 2
--					not "1001111" when address(19 downto 16) = "0011" else	-- dado = 3
--					not "1100110" when address(19 downto 16) = "0100" else	-- dado = 4
--					not "1101101" when address(19 downto 16) = "0101" else	-- dado = 5
--					not "1111101" when address(19 downto 16) = "0110" else	-- dado = 6
--					not "0000111" when address(19 downto 16) = "0111" else	-- dado = 7
--					not "1111111" when address(19 downto 16) = "1000" else	-- dado = 8
--					not "1101111" when address(19 downto 16) = "1001" else	-- dado = 9
--					not "1110111" when address(19 downto 16) = "1010" else	-- dado = 10/0xA
--					not "1111100" when address(19 downto 16) = "1011" else	-- dado = 11/0xB
--					not "0111001" when address(19 downto 16) = "1100" else	-- dado = 12/0xC
--					not "1011110" when address(19 downto 16) = "1101" else	-- dado = 13/0xD
--					not "1111001" when address(19 downto 16) = "1110" else	-- dado = 14/0xE
--					not "1110001" when address(19 downto 16) = "1111" else	-- dado = 15/0xF
--					not "0000000";
--					
--	Nibble7 <= 	not "0111111" when address(31 downto 28) = "0000" else	-- dado = 0
--					not "0000110" when address(31 downto 28) = "0001" else	-- dado = 1
--					not "1011011" when address(31 downto 28) = "0010" else	-- dado = 2
--					not "1001111" when address(31 downto 28) = "0011" else	-- dado = 3
--					not "1100110" when address(31 downto 28) = "0100" else	-- dado = 4
--					not "1101101" when address(31 downto 28) = "0101" else	-- dado = 5
--					not "1111101" when address(31 downto 28) = "0110" else	-- dado = 6
--					not "0000111" when address(31 downto 28) = "0111" else	-- dado = 7
--					not "1111111" when address(31 downto 28) = "1000" else	-- dado = 8
--					not "1101111" when address(31 downto 28) = "1001" else	-- dado = 9
--					not "1110111" when address(31 downto 28) = "1010"else	-- dado = 10/0xA
--					not "1111100" when address(31 downto 28) = "1011" else	-- dado = 11/0xB
--					not "0111001" when address(31 downto 28) = "1100" else	-- dado = 12/0xC
--					not "1011110" when address(31 downto 28) = "1101" else	-- dado = 13/0xD
--					not "1111001" when address(31 downto 28) = "1110" else	-- dado = 14/0xE
--					not "1110001" when address(31 downto 28) = "1111" else	-- dado = 15/0xF
--					not "0000000";					

					-- Entra número --> sai valor decodificado 
   Nibble0 <= 	not "0111111" when address_next_debug(3 downto 2) = "00" else	-- dado = 0
					--not "0000110" when address_next_debug(3 downto 2) = "00" else	-- dado = 1
					--not "1011011" when address_next_debug(3 downto 2) = "00" else	-- dado = 2
					--not "1001111" when address_next_debug(3 downto 2) = "00" else	-- dado = 3
					not "1100110" when address_next_debug(3 downto 2) = "01" else	-- dado = 4
					--not "1101101" when address_next_debug(3 downto 2) = "01" else	-- dado = 5
					--not "1111101" when address_next_debug(3 downto 2) = "01" else	-- dado = 6
					--not "0000111" when address_next_debug(3 downto 2) = "01" else	-- dado = 7
					not "1111111" when address_next_debug(3 downto 2) = "10" else	-- dado = 8
					--not "1101111" when address_next_debug(3 downto 2) = "10" else	-- dado = 9
					--not "1110111" when address_next_debug(3 downto 2) = "10"else	-- dado = 10
					--not "1111100" when address_next_debug(3 downto 2) = "10" else	-- dado = 11
					not "0111001" when address_next_debug(3 downto 2) = "11" else	-- dado = 12/0xC
					--not "1011110" when address_next_debug(3 downto 2) = "11" else	-- dado = 13
					--not "1111001" when address_next_debug(3 downto 2) = "11" else	-- dado = 14
					--not "1110001" when address_next_debug(3 downto 2) = "11" else	-- dado = 15
					not "0000000";
	
	Nibble1 <= 	not "0111111" when address_next_debug(7 downto 4) = "0000" else	-- dado = 0
					not "0000110" when address_next_debug(7 downto 4) = "0001" else	-- dado = 1
					not "1011011" when address_next_debug(7 downto 4) = "0010" else	-- dado = 2
					not "1001111" when address_next_debug(7 downto 4) = "0011" else	-- dado = 3
					not "1100110" when address_next_debug(7 downto 4) = "0100" else	-- dado = 4
					not "1101101" when address_next_debug(7 downto 4) = "0101" else	-- dado = 5
					not "1111101" when address_next_debug(7 downto 4) = "0110" else	-- dado = 6
					not "0000111" when address_next_debug(7 downto 4) = "0111" else	-- dado = 7
					not "1111111" when address_next_debug(7 downto 4) = "1000" else	-- dado = 8
					not "1101111" when address_next_debug(7 downto 4) = "1001" else	-- dado = 9
					not "1110111" when address_next_debug(7 downto 4) = "1010" else	-- dado = 10/0xA
					not "1111100" when address_next_debug(7 downto 4) = "1011" else	-- dado = 11/0xB
					not "0111001" when address_next_debug(7 downto 4) = "1100" else	-- dado = 12/0xC
					not "1011110" when address_next_debug(7 downto 4) = "1101" else	-- dado = 13/0xD
					not "1111001" when address_next_debug(7 downto 4) = "1110" else	-- dado = 14/0xE
					not "1110001" when address_next_debug(7 downto 4) = "1111" else	-- dado = 15/0xF
					not "0000000";
					
	Nibble2 <= 	not "0111111" when address_next_debug(11 downto 8) = "0000" else	-- dado = 0
					not "0000110" when address_next_debug(11 downto 8) = "0001" else	-- dado = 1
					not "1011011" when address_next_debug(11 downto 8) = "0010" else	-- dado = 2
					not "1001111" when address_next_debug(11 downto 8) = "0011" else	-- dado = 3
					not "1100110" when address_next_debug(11 downto 8) = "0100" else	-- dado = 4
					not "1101101" when address_next_debug(11 downto 8) = "0101" else	-- dado = 5
					not "1111101" when address_next_debug(11 downto 8) = "0110" else	-- dado = 6
					not "0000111" when address_next_debug(11 downto 8) = "0111" else	-- dado = 7
					not "1111111" when address_next_debug(11 downto 8) = "1000" else	-- dado = 8
					not "1101111" when address_next_debug(11 downto 8) = "1001" else	-- dado = 9
					not "1110111" when address_next_debug(11 downto 8) = "1010" else	-- dado = 10/0xA
					not "1111100" when address_next_debug(11 downto 8) = "1011" else	-- dado = 11/0xB
					not "0111001" when address_next_debug(11 downto 8) = "1100" else	-- dado = 12/0xC
					not "1011110" when address_next_debug(11 downto 8) = "1101" else	-- dado = 13/0xD
					not "1111001" when address_next_debug(11 downto 8) = "1110" else	-- dado = 14/0xE
					not "1110001" when address_next_debug(11 downto 8) = "1111" else	-- dado = 15/0xF
					not "0000000";
					
	Nibble3 <= 	not "0111111" when address_next_debug(15 downto 12) = "0000" else	-- dado = 0
					not "0000110" when address_next_debug(15 downto 12) = "0001" else	-- dado = 1
					not "1011011" when address_next_debug(15 downto 12) = "0010" else	-- dado = 2
					not "1001111" when address_next_debug(15 downto 12) = "0011" else	-- dado = 3
					not "1100110" when address_next_debug(15 downto 12) = "0100" else	-- dado = 4
					not "1101101" when address_next_debug(15 downto 12) = "0101" else	-- dado = 5
					not "1111101" when address_next_debug(15 downto 12) = "0110" else	-- dado = 6
					not "0000111" when address_next_debug(15 downto 12) = "0111" else	-- dado = 7
					not "1111111" when address_next_debug(15 downto 12) = "1000" else	-- dado = 8
					not "1101111" when address_next_debug(15 downto 12) = "1001" else	-- dado = 9
					not "1110111" when address_next_debug(15 downto 12) = "1010" else	-- dado = 10/0xA
					not "1111100" when address_next_debug(15 downto 12) = "1011" else	-- dado = 11/0xB
					not "0111001" when address_next_debug(15 downto 12) = "1100" else	-- dado = 12/0xC
					not "1011110" when address_next_debug(15 downto 12) = "1101" else	-- dado = 13/0xD
					not "1111001" when address_next_debug(15 downto 12) = "1110" else	-- dado = 14/0xE
					not "1110001" when address_next_debug(15 downto 12) = "1111" else	-- dado = 15/0xF
					not "0000000";
					
	Nibble4 <= 	not "0111111" when address_next_debug(19 downto 16) = "0000" else	-- dado = 0
					not "0000110" when address_next_debug(19 downto 16) = "0001" else	-- dado = 1
					not "1011011" when address_next_debug(19 downto 16) = "0010" else	-- dado = 2
					not "1001111" when address_next_debug(19 downto 16) = "0011" else	-- dado = 3
					not "1100110" when address_next_debug(19 downto 16) = "0100" else	-- dado = 4
					not "1101101" when address_next_debug(19 downto 16) = "0101" else	-- dado = 5
					not "1111101" when address_next_debug(19 downto 16) = "0110" else	-- dado = 6
					not "0000111" when address_next_debug(19 downto 16) = "0111" else	-- dado = 7
					not "1111111" when address_next_debug(19 downto 16) = "1000" else	-- dado = 8
					not "1101111" when address_next_debug(19 downto 16) = "1001" else	-- dado = 9
					not "1110111" when address_next_debug(19 downto 16) = "1010" else	-- dado = 10/0xA
					not "1111100" when address_next_debug(19 downto 16) = "1011" else	-- dado = 11/0xB
					not "0111001" when address_next_debug(19 downto 16) = "1100" else	-- dado = 12/0xC
					not "1011110" when address_next_debug(19 downto 16) = "1101" else	-- dado = 13/0xD
					not "1111001" when address_next_debug(19 downto 16) = "1110" else	-- dado = 14/0xE
					not "1110001" when address_next_debug(19 downto 16) = "1111" else	-- dado = 15/0xF
					not "0000000";
					
	Nibble7 <= 	not "0111111" when address_next_debug(31 downto 28) = "0000" else	-- dado = 0
					not "0000110" when address_next_debug(31 downto 28) = "0001" else	-- dado = 1
					not "1011011" when address_next_debug(31 downto 28) = "0010" else	-- dado = 2
					not "1001111" when address_next_debug(31 downto 28) = "0011" else	-- dado = 3
					not "1100110" when address_next_debug(31 downto 28) = "0100" else	-- dado = 4
					not "1101101" when address_next_debug(31 downto 28) = "0101" else	-- dado = 5
					not "1111101" when address_next_debug(31 downto 28) = "0110" else	-- dado = 6
					not "0000111" when address_next_debug(31 downto 28) = "0111" else	-- dado = 7
					not "1111111" when address_next_debug(31 downto 28) = "1000" else	-- dado = 8
					not "1101111" when address_next_debug(31 downto 28) = "1001" else	-- dado = 9
					not "1110111" when address_next_debug(31 downto 28) = "1010" else	-- dado = 10/0xA
					not "1111100" when address_next_debug(31 downto 28) = "1011" else	-- dado = 11/0xB
					not "0111001" when address_next_debug(31 downto 28) = "1100" else	-- dado = 12/0xC
					not "1011110" when address_next_debug(31 downto 28) = "1101" else	-- dado = 13/0xD
					not "1111001" when address_next_debug(31 downto 28) = "1110" else	-- dado = 14/0xE
					not "1110001" when address_next_debug(31 downto 28) = "1111" else	-- dado = 15/0xF
					not "0000000";					
		
	HEX0 	<= Nibble0;
	HEX1 	<= Nibble1;
	HEX2 	<= Nibble2;
--	HEX3 	<= Nibble3;
	HEX3 	<= Nibble4;	--Parte do endereço que define qual memória RAM é acessada
	HEX4	<= Nibble7;	

end; --architecture logic	
