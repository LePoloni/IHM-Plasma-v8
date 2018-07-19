---------------------------------------------------------------------
-- TITLE: Random Access Memory
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 4/21/01
-- FILENAME: ram.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Implements the RAM, reads the executable from either "code.txt",
--    or for Altera "code[0-3].hex".
--    Modified from "The Designer's Guide to VHDL" by Peter J. Ashenden

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 19/7/16 (vide também ram_leandro.vhd)
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
--Pelo que entendi a megafunction que gera memória RAM da Altera
--cria memórias de 8 bits, por conta disso quatro memórias foram
--criadas. Cada uma delas armazena um byte do 4 que formam os dados e
--as instruções. Por conta disso o programa original precisa ser
--separado em 4 programas chamadas de code0.txt, code1.txt, 
--code2.txt e code3.txt (tosco mas deve funcionar).
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- MODIFICADO: 
-- 30/11/16 - Substitui "use work.mlite_pack.all;"
--					por "use work.mlite_pack_mod.all;"
-- 28/12/31 - Alterei o tamanho da RAM para suportar até 16 tarefas
--				  constant ADDRESS_WIDTH   : natural := 10 --> 11
--				- Assim que iniciei a versão 4 do projeto precisei 
--				  reverter essa modificação para conseguir sintetisar
-- 02/08/17 - Criei um generic para definir a quantidade de bits de endereço
--				  da memória ram, dessa forma poderei criar memórias com
--				  diferentes tamanhos (memory_size)
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.mlite_pack_mod.all;

entity ram is
   --generic(memory_type : string := "DEFAULT");
	generic(memory_type : string := "ALTERA_LPM";
			  memory_size : natural := 14);	--13 é o valor dafault (2^13 Bytes = 8kB = 2kWords)
   port(clk               : in std_logic;
        enable            : in std_logic;
        write_byte_enable : in std_logic_vector(3 downto 0);
        address           : in std_logic_vector(31 downto 2);
--		  address           : in std_logic_vector(29 downto 0);	--Somente para teste no simulador
        data_write        : in std_logic_vector(31 downto 0);
        data_read         : out std_logic_vector(31 downto 0));
end; --entity ram

architecture logic of ram is
   --constant ADDRESS_WIDTH   : natural := 13;	--8KB = 2KWords
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
	--Alterações para leitura de programa de teste para kit Terasic
--	constant ADDRESS_WIDTH   : natural := 10;		--1KB = 256Words
	--Alterações para permitir até 16 tarefas (28/12/16)
--	constant ADDRESS_WIDTH   : natural := 11;		--2KB = 512Words (8 tarefas/64B)
	constant ADDRESS_WIDTH   : natural := memory_size;		--2^memory_size Bytes
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
begin

   generic_ram:
   if memory_type /= "ALTERA_LPM" generate 
   begin
   --Simulate a synchronous RAM
   ram_proc: process(clk, enable, write_byte_enable, 
         address, data_write) --mem_write, mem_sel
      variable mem_size : natural := 2 ** ADDRESS_WIDTH;
      variable data : std_logic_vector(31 downto 0); 
      subtype word is std_logic_vector(data_write'length-1 downto 0);
      type storage_array is
         array(natural range 0 to mem_size/4 - 1) of word;
      variable storage : storage_array;
      variable index : natural := 0;
      --file load_file : text open read_mode is "code.txt";
		file load_file : text open read_mode is "Plasma_IOs.txt";
      variable hex_file_line : line;
   begin

--      --Load in the ram executable image
--      if index = 0 then
--         while not endfile(load_file) loop
----The following two lines had to be commented out for synthesis
--            readline(load_file, hex_file_line);
--            hread(hex_file_line, data);
--            storage(index) := data;
--            index := index + 1;
--         end loop;
--      end if;

      if rising_edge(clk) then
         index := conv_integer(address(ADDRESS_WIDTH-1 downto 2));
         --data := storage(index);

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
			--Alterações para leitura de programa de teste para kit Terasic
			--Plasma_IOs.asm
			case index is
				--GIO0 <- GPIOA
--				when 0 => data := X"3c1c2000";
--				when 1 => data := X"8f890050";
--				when 2 => data := X"af890030";
--				when 3 => data := X"01204027";
--				when 4 => data := X"af880040";
--				when 5 => data := X"0c000007";
--				when 6 => data := X"08000001";
--				when 7 => data := X"240a0001";
--				when 8 => data := X"240b0001";
--				when 9 => data := X"014b5022";
--				when 10 => data := X"1540fffe";
--				when 11 => data := X"03e00008";
				
				--Tasks_simples
				when 0 => data := X"3c1c2000";
				when 1 => data := X"240900ff";
				when 2 => data := X"af890040";
				when 3 => data := X"8f890050";
				when 4 => data := X"312900ff";
				when 5 => data := X"af890030";
				when 6 => data := X"24090001";
				when 7 => data := X"24080001";
				when 8 => data := X"01284822";
				when 9 => data := X"1520fffe";
				when 10 => data := X"08000001";
				when 11 => data := X"8f8a0050";
				when 12 => data := X"314a0200";
				when 13 => data := X"1140fffd";
				when 14 => data := X"8f8a0030";
				when 15 => data := X"314a0200";
				when 16 => data := X"11400003";
				when 17 => data := X"240a0200";
				when 18 => data := X"af8a0040";
				when 19 => data := X"08000016";
				when 20 => data := X"240a0200";
				when 21 => data := X"af8a0030";
				when 22 => data := X"3c010001";
				when 23 => data := X"342a86a0";
				when 24 => data := X"240b0001";
				when 25 => data := X"014b5022";
				when 26 => data := X"1540fffe";
				when 27 => data := X"08000001";
				when others => data := storage(index);
			end case;
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

         if enable = '1' then
            if write_byte_enable(0) = '1' then
               data(7 downto 0) := data_write(7 downto 0);
            end if;
            if write_byte_enable(1) = '1' then
               data(15 downto 8) := data_write(15 downto 8);
            end if;
            if write_byte_enable(2) = '1' then
               data(23 downto 16) := data_write(23 downto 16);
            end if;
            if write_byte_enable(3) = '1' then
               data(31 downto 24) := data_write(31 downto 24);
            end if;
         end if;
      
         if write_byte_enable /= "0000" then
            storage(index) := data;
         end if;
      end if;

      data_read <= data;
   end process;
   end generate; --generic_ram


   altera_ram:
   if memory_type = "ALTERA_LPM" generate
      signal byte_we : std_logic_vector(3 downto 0);
   begin
      byte_we <= write_byte_enable when enable = '1' else "0000";
      lpm_ram_io_component0 : lpm_ram_dq
         GENERIC MAP (
            intended_device_family => "UNUSED",
            lpm_width => 8,
            lpm_widthad => ADDRESS_WIDTH-2,
            lpm_indata => "REGISTERED",
            lpm_address_control => "REGISTERED",
            lpm_outdata => "UNREGISTERED",
            lpm_file => "code0.hex",		--C
				--lpm_file => "code3.hex",		--Assembly
				--lpm_file => "tasks_code3.hex",
				--lpm_file => "tasks_simple_code3.hex",
				--lpm_file => "55code3.hex",
            use_eab => "ON",
            lpm_type => "LPM_RAM_DQ")
         PORT MAP (
            data    => data_write(31 downto 24),
            address => address(ADDRESS_WIDTH-1 downto 2),
            inclock => clk,
            we      => byte_we(3),
            q       => data_read(31 downto 24));

      lpm_ram_io_component1 : lpm_ram_dq
         GENERIC MAP (
            intended_device_family => "UNUSED",
            lpm_width => 8,
            lpm_widthad => ADDRESS_WIDTH-2,
            lpm_indata => "REGISTERED",
            lpm_address_control => "REGISTERED",
            lpm_outdata => "UNREGISTERED",
            lpm_file => "code1.hex",		--C
            --lpm_file => "code2.hex",		--Assembly
				--lpm_file => "tasks_code2.hex",
				--lpm_file => "tasks_simple_code2.hex",
				--lpm_file => "55code2.hex",
				use_eab => "ON",
            lpm_type => "LPM_RAM_DQ")
         PORT MAP (
            data    => data_write(23 downto 16),
            address => address(ADDRESS_WIDTH-1 downto 2),
            inclock => clk,
            we      => byte_we(2),
            q       => data_read(23 downto 16));

      lpm_ram_io_component2 : lpm_ram_dq
         GENERIC MAP (
            intended_device_family => "UNUSED",
            lpm_width => 8,
            lpm_widthad => ADDRESS_WIDTH-2,
            lpm_indata => "REGISTERED",
            lpm_address_control => "REGISTERED",
            lpm_outdata => "UNREGISTERED",
            lpm_file => "code2.hex",		--C
				--lpm_file => "code1.hex",		--Assembly
				--lpm_file => "tasks_code1.hex",
				--lpm_file => "tasks_simple_code1.hex",
				--lpm_file => "55code1.hex",
            use_eab => "ON",
            lpm_type => "LPM_RAM_DQ")
         PORT MAP (
            data    => data_write(15 downto 8),
            address => address(ADDRESS_WIDTH-1 downto 2),
            inclock => clk,
            we      => byte_we(1),
            q       => data_read(15 downto 8));

      lpm_ram_io_component3 : lpm_ram_dq
         GENERIC MAP (
            intended_device_family => "UNUSED",
            lpm_width => 8,
            lpm_widthad => ADDRESS_WIDTH-2,
            lpm_indata => "REGISTERED",
            lpm_address_control => "REGISTERED",
            lpm_outdata => "UNREGISTERED",
            lpm_file => "code3.hex",		--C
				--lpm_file => "code0.hex",		--Assembly
				--lpm_file => "tasks_code0.hex",
				--lpm_file => "tasks_simple_code0.hex",
				--lpm_file => "55code0.hex",
				use_eab => "ON",
            lpm_type => "LPM_RAM_DQ")
         PORT MAP (
            data    => data_write(7 downto 0),
            address => address(ADDRESS_WIDTH-1 downto 2),
            inclock => clk,
            we      => byte_we(0),
            q       => data_read(7 downto 0));

   end generate; --altera_ram


   --For XILINX see ram_xilinx.vhd

end; --architecture logic
