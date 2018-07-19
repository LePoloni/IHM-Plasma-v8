---------------------------------------------------------------------
-- TITLE: Memory Controller
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 1/31/01
-- FILENAME: mem_ctrl.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Memory controller for the Plasma CPU.
--    Supports Big or Little Endian mode.
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 10/7/16 e 11/7/16
-- MODIFICADO: 30/11/16 - Substitui use work.mlite_pack.all;
--	por use work.mlite_pack_mod.all;
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.mlite_pack_mod.all;

entity mem_ctrl is
   port(clk          : in std_logic;								--Reseta a máquina
        reset_in     : in std_logic;								--Bloqueia a execusão de operações
        pause_in     : in std_logic;								--Força uma operação nula (bolha?)
        nullify_op   : in std_logic;								--Anula a próxima operação
        address_pc   : in std_logic_vector(31 downto 2);		--End. da próxima instrução
        opcode_out   : out std_logic_vector(31 downto 0);	--Instrução a ser executada (segue um controle e jump pc)

        address_in   : in std_logic_vector(31 downto 0);
        mem_source   : in mem_source_type;						--***Define o tipo de acesso às memórias (R/W) e a quantidade de bits (32/16/8)
        data_write   : in std_logic_vector(31 downto 0);		--Dado a ser escrito
        data_read    : out std_logic_vector(31 downto 0);	--Dado lido
        pause_out    : out std_logic;								--Pausa as operações
        
        address_next : out std_logic_vector(31 downto 2);	--Próximo endereço a ser acessado da memória interna (RAM ou cache)
        byte_we_next : out std_logic_vector(3 downto 0);		--Define o conjunto de bytes a ser escrito de um endereço (independente do clock)

        address      : out std_logic_vector(31 downto 2);	--Próximo endereço a ser acessado da memória externa (não usado)
        byte_we      : out std_logic_vector(3 downto 0);		--Define o conjunto de bytes a ser escrito de um endereço
        data_w       : out std_logic_vector(31 downto 0);
        data_r       : in std_logic_vector(31 downto 0));	--Entrada com o Opcode selecionado
end; --entity mem_ctrl

architecture logic of mem_ctrl is
   --"00" = big_endian; "11" = little_endian
	--Big_endian = maior endereço da memória armazena o byte menos significativo
	--Little_endian = menor endereço da memória armazena o byte menos significativo
   constant ENDIAN_MODE   : std_logic_vector(1 downto 0) := "00";
   --Sinais internos auxiliares
	signal opcode_reg      : std_logic_vector(31 downto 0);
   signal next_opcode_reg : std_logic_vector(31 downto 0);
   signal address_reg     : std_logic_vector(31 downto 2);
   signal byte_we_reg     : std_logic_vector(3 downto 0);

   signal mem_state_reg   : std_logic;
   constant STATE_ADDR    : std_logic := '0';
   constant STATE_ACCESS  : std_logic := '1';

begin
--Processo sensível a todos os ports de entrada e sinais auxiliares
mem_proc: process(clk, reset_in, pause_in, nullify_op, 
                  address_pc, address_in, mem_source, data_write, 
                  data_r, opcode_reg, next_opcode_reg, mem_state_reg,
                  address_reg, byte_we_reg)
   variable address_var    : std_logic_vector(31 downto 2);
   variable data_read_var  : std_logic_vector(31 downto 0);
   variable data_write_var : std_logic_vector(31 downto 0);
   variable opcode_next    : std_logic_vector(31 downto 0);
   variable byte_we_var    : std_logic_vector(3 downto 0);
   variable mem_state_next : std_logic;
   variable pause_var      : std_logic;
   variable bits           : std_logic_vector(1 downto 0);
begin
	--Inicialização das variáveis locais
   byte_we_var := "0000";
   pause_var := '0';
   data_read_var := ZERO;
   data_write_var := ZERO;
   mem_state_next := mem_state_reg;
   opcode_next := opcode_reg;

	--Analisa o tipod de acesso às memórias
   case mem_source is
   
	----------------------------------------------------------------------------
	--Operações que definem o valor de data_read_var (leitura de dados)---------
	
	--Se for leitura de 32 bits
	when MEM_READ32 =>				
      data_read_var := data_r;	--Lê a entrada data_r

	--Se for leitura de 16 bits
   when MEM_READ16 | MEM_READ16S =>
      
		--Se o bit 1 do endereço é igual ao bit 1 do tipo de memória
		if address_in(1) = ENDIAN_MODE(1) then
         --Lê os 16 msbs
			data_read_var(15 downto 0) := data_r(31 downto 16);
      else
			--Lê os 16 lsbs
         data_read_var(15 downto 0) := data_r(15 downto 0);
      end if;
      
		--Se o tipo de acesso é de 16 bits sem sinal ou o bit 15 do dado lido é igual a 0 (valor positivo)
		if mem_source = MEM_READ16 or data_read_var(15) = '0' then
			--Os 16 msbs são iguais a 0
         data_read_var(31 downto 16) := ZERO(31 downto 16);
      else
			--Os 16 msbs são iguais a 1 (valor negativo)
         data_read_var(31 downto 16) := ONES(31 downto 16);
      end if;

   --Se for leitura de 8 bits
	when MEM_READ8 | MEM_READ8S =>
		
		--Faz um xor entre os lsbs do endereço e o tipo de memória
      bits := address_in(1 downto 0) xor ENDIAN_MODE;
		--Se for big-endian (00)
		--bits = address_in(1 downto 0)
		--Se for little-endian (11)
		--bits = NOT(address_in(1 downto 0))		
		
		--Define o byte a ser lido dentre 4 possibilidade
      case bits is
      when "00" => data_read_var(7 downto 0) := data_r(31 downto 24);
      when "01" => data_read_var(7 downto 0) := data_r(23 downto 16);
      when "10" => data_read_var(7 downto 0) := data_r(15 downto 8);
      when others => data_read_var(7 downto 0) := data_r(7 downto 0);
      end case;
      
		--Se o tipo de acesso é de 8 bits sem sinal ou o bit 7 do dado lido é igual a 0 (valor positivo)
		if mem_source = MEM_READ8 or data_read_var(7) = '0' then
         --Os 24 msbs são iguais a 0
			data_read_var(31 downto 8) := ZERO(31 downto 8);
      else
			--Os 24 msbs são iguais a 1 (valor negativo)
         data_read_var(31 downto 8) := ONES(31 downto 8);
      end if;

	----------------------------------------------------------------------------
	--Operações que definem o valor de data_write_var (escrita de dados)--------
	
	--Se for escrita de 32 bits
   when MEM_WRITE32 =>
      data_write_var := data_write;		--Escreve a entrada data_write
      byte_we_var := "1111";

	--Se for escrita de 16 bits
   when MEM_WRITE16 =>
		
		--Concatena dois vezes o 16 lsbs
      data_write_var := data_write(15 downto 0) & data_write(15 downto 0);
      
		--Se o bit 1 do endereço é igual ao bit 1 do tipo de memória
		if address_in(1) = ENDIAN_MODE(1) then
         --Define o tipo de escrita como 1100 (imagino que sejam os dois msBs)
			byte_we_var := "1100";
      else
			--Define o tipo de escrita como 0011 (imagino que sejam os dois lsBs)
         byte_we_var := "0011";
      end if;

	--Se for escrita de 8 bits
   when MEM_WRITE8 =>
		
		--Concatena quatro vezes o 8 lsbs
      data_write_var := data_write(7 downto 0) & data_write(7 downto 0) &
                  data_write(7 downto 0) & data_write(7 downto 0);
      
		--Faz um xor entre os lsbs do endereço e o tipo de memória
		bits := address_in(1 downto 0) xor ENDIAN_MODE;
      --Se for big-endian (00)
		--bits = address_in(1 downto 0)
		--Se for little-endian (11)
		--bits = NOT(address_in(1 downto 0))		
		
		--Define o tipo de escrita dentre 4 possibilidade (imagino que 1 representa a posição do byte)		
		case bits is
      when "00" =>
         byte_we_var := "1000"; 
      when "01" => 
         byte_we_var := "0100"; 
      when "10" =>
         byte_we_var := "0010"; 
      when others =>
         byte_we_var := "0001"; 
      end case;

   when others =>
   end case;

	----------------------------------------------------------------------------
	--Operação que define uma busca de instrução (programa)----------------------
	
	--Se for uma busca de instrução
   if mem_source = MEM_FETCH then --opcode fetch
      
		--Endereço = PC
		address_var := address_pc;
		--Próximo Opcode = data_r
      opcode_next := data_r;
      --Estado passa para STATE_ADDR (0)
		mem_state_next := STATE_ADDR;
   
	--Se não for uma busca de instrução
	else
		
		--Se está em estado STATE_ADDR (0)
      if mem_state_reg = STATE_ADDR then
         
			--Se não está pausado
			if pause_in = '0' then
            
				--Endereço = address_in
				address_var := address_in(31 downto 2);
            --Estado passa para STATE_ACCESS (1)
				mem_state_next := STATE_ACCESS;
            --pause_var passa para 1;
				pause_var := '1';
         
			else
			
				--Endereço = address_pc
            address_var := address_pc;
				--Define o tipo de escrita em nulo
            byte_we_var := "0000";
         
			end if;
		
		--Se está em estado STATE_ACCESS (1)	
      else  --STATE_ACCESS
         
			--Se não está pausado
			if pause_in = '0' then
            
				--Endereço = address_pc
				address_var := address_pc;
            --Define o próximo Opcode
				opcode_next := next_opcode_reg;
            --Estado passa para STATE_ADDR (0)
				mem_state_next := STATE_ADDR;
            --Define o tipo de escrita em nulo
				byte_we_var := "0000";
         
			else
			
				--Endereço = address_in
            address_var := address_in(31 downto 2);
				--Define o tipo de escrita em nulo
            byte_we_var := "0000";
				
         end if;
      end if;
   end if;

	--Se é uma operação nula e não está pausado
   if nullify_op = '1' and pause_in = '0' then
      
		--Define o próximo Opcode como NOP
		opcode_next := ZERO;  --NOP after beql
		
   end if;

   --Se está resetando
	if reset_in = '1' then
	
		--Estado passa para STATE_ADDR (0)
      mem_state_reg <= STATE_ADDR;
		--Define o registrador de Opcode como 0
      opcode_reg <= ZERO;
		--Define o próximo Opcode como 0
      next_opcode_reg <= ZERO;
      --Define o endereço do registrador como 0
		address_reg <= ZERO(31 downto 2);
		--Define o tipo de escrita em nulo
      byte_we_reg <= "0000";
	
	--	Senão se for uma borda de subida do clock
   elsif rising_edge(clk) then
      
		--Se não está pausado
		if pause_in = '0' then
         --Atualiza registrador de endereço
			address_reg <= address_var;
			--Atualiza o tipo de escrita
         byte_we_reg <= byte_we_var;
			--Atualiza o estado da memória (endereçamento (ADDR) ou acesso (ACCESS)
         mem_state_reg <= mem_state_next;
			--Atualiza o próximo Opcode
			opcode_reg <= opcode_next;
         
			--Se está em estado STATE_ADDR (0)
			if mem_state_reg = STATE_ADDR then
            
				--Atualiza o próximo Opcode
				next_opcode_reg <= data_r;
				
         end if;
      end if;
   end if;

	--Atualiza as saídas do bloco
	opcode_out <= opcode_reg;
   data_read <= data_read_var;
   pause_out <= pause_var;

   address_next <= address_var;
   byte_we_next <= byte_we_var;

   address <= address_reg;
   byte_we <= byte_we_reg;
   data_w <= data_write_var;

end process; --data_proc

end; --architecture logic
