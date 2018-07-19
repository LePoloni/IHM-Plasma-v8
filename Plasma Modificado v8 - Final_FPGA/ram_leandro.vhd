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
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.mlite_pack.all;
--Leandro---------------------------------
use IEEE.NUMERIC_STD.ALL;
--Leandro---------------------------------

entity ram_leandro is
   generic(memory_type : string := "DEFAULT");
   port(clk               : in std_logic;
        enable            : in std_logic;
        write_byte_enable : in std_logic_vector(3 downto 0);
        address           : in std_logic_vector(31 downto 2);
        data_write        : in std_logic_vector(31 downto 0);
        data_read         : out std_logic_vector(31 downto 0)     ;

--Leandro---------------------------------------		  
		  data_read_rom     : out std_logic_vector(7 downto 0);
		  address_rom       : in std_logic_vector(6 downto 0)
--Leandro---------------------------------------


		  );
end; --entity ram

architecture logic of ram_leandro is

--CRIAÇÃO DE UMA RAM===========================================================
	constant ADDRESS_WIDTH   : natural := 13;
	
	signal mem_size : natural := 2 ** ADDRESS_WIDTH;
   signal data : std_logic_vector(31 downto 0); 
   subtype word is std_logic_vector(data_write'length-1 downto 0);
   type storage_array is array(natural range 0 to mem_size/4 - 1) of word;
   --variable storage : storage_array;
	
	--A função precisa ser do tipo IMPURE (pesquisar seu sentido!!!)
	IMPURE FUNCTION init_ram RETURN storage_array IS
		FILE ram_file   : text OPEN read_mode IS "code.txt";	--O arquivo deve estar na pasta do testbench
		
		VARIABLE ret    : storage_array;
		VARIABLE l      : line;
	BEGIN
		FOR i IN 0 TO 20 LOOP
			IF(NOT ENDFILE(ram_file)) THEN
				readline(ram_file, l);
				hread(l, ret(i));
			
			END IF;
		END LOOP;
		
		RETURN ret;
	END FUNCTION init_ram;
	
	--variable storage : storage_array := init_ram;
--FIM DA CRIAÇÃO DA RAM========================================================	

--CRIAÇÃO DE UMA ROM===========================================================
	 type rom_t is array(0 to 63) of std_logic_vector(7 downto 0);
	
	--A função precisa ser do tipo IMPURE (pesquisar seu sentido!!!)
	IMPURE FUNCTION init_rom RETURN rom_t IS
		FILE rom_file   : text OPEN read_mode IS "rom_leandro.txt";	--O arquivo deve estar na pasta do testbench
		
		FILE out_file   : text IS OUT "out_leandro.txt";
		
		VARIABLE ret    : rom_t;
		VARIABLE l      : line;
	BEGIN
		FOR i IN 0 TO 63 LOOP
			IF(NOT ENDFILE(rom_file)) THEN
				readline(rom_file, l);
				hread(l, ret(i));
				
				writeline(out_file, l);
				
			END IF;
		END LOOP;
		
		RETURN ret;
	END FUNCTION init_rom;
	
	CONSTANT ROM    : rom_t := init_rom;		--Funciona do Modelsim
	--signal ROM    : rom_t := init_rom;		--Funciona do Modelsim
--FIM DA CRIAÇÃO DA ROM========================================================

--Leandro: Mudança da posição de carga da RAM, RAM síncrona ao invés de assíncrona
--      variable mem_size : natural := 2 ** ADDRESS_WIDTH;
--      variable data : std_logic_vector(31 downto 0); 
--      subtype word is std_logic_vector(data_write'length-1 downto 0);
--      type storage_array is
--         array(natural range 0 to mem_size/4 - 1) of word;
--      variable storage : storage_array;
--      variable index : natural := 0;
--      file load_file : text open read_mode is "code2.txt";
--      variable hex_file_line : line;
--
----		if index = 0 then
--         --while not endfile(load_file) loop
--			while (not endfile(load_file)) AND (index < 20) loop
----The following two lines had to be commented out for synthesis
--            readline(load_file, hex_file_line);
--            hread(hex_file_line, data);
--            storage(index) := data;
--            index := index + 1;
--         end loop;
----      end if;	
---------------------------------------------------------------------------------	
	
begin
	--Lê a ROM de forma assíncrona
	data_read_rom <= ROM( conv_integer( address_rom ) ) ;

   generic_ram:
   if memory_type /= "ALTERA_LPM" generate 
	--signal ROM    : rom_t := init_rom; --Tipo 1 ok
	
	--signal storage : storage_array := init_ram;
	
   begin
	
   --Simulate a synchronous RAM
   ram_proc: process(clk, enable, write_byte_enable, 
         address, data_write) --mem_write, mem_sel

--      variable mem_size : natural := 2 ** ADDRESS_WIDTH;

      variable data : std_logic_vector(31 downto 0); 

--     subtype word is std_logic_vector(data_write'length-1 downto 0);
--      type storage_array is
--         array(natural range 0 to mem_size/4 - 1) of word;
--      variable storage : storage_array;

      variable index : natural := 0;

--      file load_file : text open read_mode is "code2.txt"; --O arquivo deve estar na pasta do testbench
--      variable hex_file_line : line;
   
	

	variable storage : storage_array := init_ram;

begin
--
      --Load in the ram executable image
--      if index = 0 then
--         --while not endfile(load_file) loop
--			while (not endfile(load_file)) AND (index < 20) loop
----The following two lines had to be commented out for synthesis
--            readline(load_file, hex_file_line);
--            hread(hex_file_line, data);
--            storage(index) := data;
--            index := index + 1;
--         end loop;
--      end if;

      if rising_edge(clk) then
         index := conv_integer(address(ADDRESS_WIDTH-1 downto 2));
         data := storage(index);

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

--Leandro---------------------------------------
	--data_read_rom <= ROM( conv_integer( address_rom ) ) ;	--Tipo 1 ok

--Leandro---------------------------------------
end generate; --generic_ram

--   altera_ram:
--   if memory_type = "ALTERA_LPM" generate
--      signal byte_we : std_logic_vector(3 downto 0);
--   begin
--      byte_we <= write_byte_enable when enable = '1' else "0000";
--      lpm_ram_io_component0 : lpm_ram_dq
--         GENERIC MAP (
--            intended_device_family => "UNUSED",
--            lpm_width => 8,
--            lpm_widthad => ADDRESS_WIDTH-2,
--            lpm_indata => "REGISTERED",
--            lpm_address_control => "REGISTERED",
--            lpm_outdata => "UNREGISTERED",
--            lpm_file => "code0.hex",
--            use_eab => "ON",
--            lpm_type => "LPM_RAM_DQ")
--         PORT MAP (
--            data    => data_write(31 downto 24),
--            address => address(ADDRESS_WIDTH-1 downto 2),
--            inclock => clk,
--            we      => byte_we(3),
--            q       => data_read(31 downto 24));
--
--      lpm_ram_io_component1 : lpm_ram_dq
--         GENERIC MAP (
--            intended_device_family => "UNUSED",
--            lpm_width => 8,
--            lpm_widthad => ADDRESS_WIDTH-2,
--            lpm_indata => "REGISTERED",
--            lpm_address_control => "REGISTERED",
--            lpm_outdata => "UNREGISTERED",
--            lpm_file => "code1.hex",
--            use_eab => "ON",
--            lpm_type => "LPM_RAM_DQ")
--         PORT MAP (
--            data    => data_write(23 downto 16),
--            address => address(ADDRESS_WIDTH-1 downto 2),
--            inclock => clk,
--            we      => byte_we(2),
--            q       => data_read(23 downto 16));
--
--      lpm_ram_io_component2 : lpm_ram_dq
--         GENERIC MAP (
--            intended_device_family => "UNUSED",
--            lpm_width => 8,
--            lpm_widthad => ADDRESS_WIDTH-2,
--            lpm_indata => "REGISTERED",
--            lpm_address_control => "REGISTERED",
--            lpm_outdata => "UNREGISTERED",
--            lpm_file => "code2.hex",
--            use_eab => "ON",
--            lpm_type => "LPM_RAM_DQ")
--         PORT MAP (
--            data    => data_write(15 downto 8),
--            address => address(ADDRESS_WIDTH-1 downto 2),
--            inclock => clk,
--            we      => byte_we(1),
--            q       => data_read(15 downto 8));
--
--      lpm_ram_io_component3 : lpm_ram_dq
--         GENERIC MAP (
--            intended_device_family => "UNUSED",
--            lpm_width => 8,
--            lpm_widthad => ADDRESS_WIDTH-2,
--            lpm_indata => "REGISTERED",
--            lpm_address_control => "REGISTERED",
--            lpm_outdata => "UNREGISTERED",
--            lpm_file => "code3.hex",
--            use_eab => "ON",
--            lpm_type => "LPM_RAM_DQ")
--         PORT MAP (
--            data    => data_write(7 downto 0),
--            address => address(ADDRESS_WIDTH-1 downto 2),
--            inclock => clk,
--            we      => byte_we(0),
--            q       => data_read(7 downto 0));
--
--   end generate; --altera_ram


   --For XILINX see ram_xilinx.vhd

end; --architecture logic
