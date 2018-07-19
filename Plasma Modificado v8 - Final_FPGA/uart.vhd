---------------------------------------------------------------------
-- TITLE: UART
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 5/29/02
-- FILENAME: uart.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Implements the UART.

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 16/7/16
-- MODIFICADO: 30/11/16 - Substitui use work.mlite_pack.all;
--	por use work.mlite_pack_mod.all;	
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_textio.all;
use ieee.std_logic_unsigned.all;
use std.textio.all;
use work.mlite_pack_mod.all;

entity uart is
   generic(log_file : string := "UNUSED");
   port(clk          : in std_logic;
        reset        : in std_logic;
        enable_read  : in std_logic;
        enable_write : in std_logic;
        data_in      : in std_logic_vector(7 downto 0);
        data_out     : out std_logic_vector(7 downto 0);
        uart_read    : in std_logic;
        uart_write   : out std_logic;
        busy_write   : out std_logic;
        data_avail   : out std_logic);
end; --entity uart

architecture logic of uart is
   signal delay_write_reg : std_logic_vector(9 downto 0);
   signal bits_write_reg  : std_logic_vector(3 downto 0);
   signal data_write_reg  : std_logic_vector(8 downto 0);
   signal delay_read_reg  : std_logic_vector(9 downto 0);
   signal bits_read_reg   : std_logic_vector(3 downto 0);
   signal data_read_reg   : std_logic_vector(7 downto 0);
   signal data_save_reg   : std_logic_vector(17 downto 0);
   signal busy_write_sig  : std_logic;
   signal read_value_reg  : std_logic_vector(6 downto 0);
   signal uart_read2      : std_logic;

begin

--Processo sensível praticamente todos os ports e sinais
uart_proc: process(clk, reset, enable_read, enable_write, data_in,
                   data_write_reg, bits_write_reg, delay_write_reg, 
                   data_read_reg, bits_read_reg, delay_read_reg,
                   data_save_reg, read_value_reg, uart_read2,
                   busy_write_sig, uart_read)
	
	--Ajuste de baudrate para 57600 bps
   constant COUNT_VALUE : std_logic_vector(9 downto 0) :=
--      "0100011110";  --33MHz/2/57600Hz = 0x11e
--      "1101100100";  --50MHz/57600Hz = 0x364
      "0110110010";  --25MHz/57600Hz = 0x1b2 -- Plasma IF uses div2
--      "0011011001";  --12.5MHz/57600Hz = 0xd9
--      "0000000100";  --for debug (shorten read_value_reg)
begin
	--Lê o estado no msb do registrador de recepção
   uart_read2 <= read_value_reg(read_value_reg'length - 1);

   --Condição de reset (zero tudo com exceção de read_value_reg)
	if reset = '1' then
      data_write_reg  <= ZERO(8 downto 1) & '1';
      bits_write_reg  <= "0000";
      delay_write_reg <= ZERO(9 downto 0);
      read_value_reg  <= ONES(read_value_reg'length-1 downto 0);
      data_read_reg   <= ZERO(7 downto 0);
      bits_read_reg   <= "0000";
      delay_read_reg  <= ZERO(9 downto 0);
      data_save_reg   <= ZERO(17 downto 0);
   
	--Senão se for uma borda de subida do clock
	elsif rising_edge(clk) then

      --Write UART
		-- Bits saem pela direita (lsb)
		--Se não tem mais bits a enviar
      if bits_write_reg = "0000" then               --nothing left to write?
         --Se a escrita está habilitada
			if enable_write = '1' then
				--Zera o delay de envio entre bits
            delay_write_reg <= ZERO(9 downto 0);    --delay before next bit
            --Define o número de bits para enviar (10 bits -> 1 start + 8 dados + 1 stop)
				bits_write_reg <= "1010";               --number of bits to write
            --Define o valor do registrador de envio (8 dados + 1 start bit (0))
				data_write_reg <= data_in & '0';        --remember data & start bit
         end if;
      
		--Senão
		else
			--Se ainda não alcançou o tempo de delay entre bits
         if delay_write_reg /= COUNT_VALUE then
            --Incrementa o contador
				delay_write_reg <= delay_write_reg + 1; --delay before next bit
         --Senão
			else
				--Zera o delay de envio entre bits
            delay_write_reg <= ZERO(9 downto 0);    --reset delay
            --Decrementa a quantidade de bits a enviar
				bits_write_reg <= bits_write_reg - 1;   --bits left to write
            --Atualiza o registrador de envio com um bit a menos e o stop bit (1);
				data_write_reg <= '1' & data_write_reg(8 downto 1);
         end if;
      end if;

      --Average uart_read signal
      --Se for para executar recepção
		if uart_read = '1' then
			--Se o valor do registrador de recepção é diferente de 3Fh
         if read_value_reg /= ONES(read_value_reg'length - 1 downto 0) then
            --Incrementa 1 ao registrador de recepção
				read_value_reg <= read_value_reg + 1;
         end if;
      --Senão
		else
			--Se o valor do registrador de recepção é diferente de 0
         if read_value_reg /= ZERO(read_value_reg'length - 1 downto 0) then
            --Decrementa 1 no registrador de recepção
				read_value_reg <= read_value_reg - 1;
         end if;
      end if;

      --Read UART
		-- Bits entram pela esquerda (msb)
		--Se o delay de recepção entre bits está zerado
      if delay_read_reg = ZERO(9 downto 0) then     --done delay for read?
         --Se não falta mais nenhum bit para ler
			if bits_read_reg = "0000" then             --nothing left to read?
            --Se o msb = 0 é porque chegou o start bit
				if uart_read2 = '0' then                --wait for start bit
               --Carrega metade do valor do delay entre bits
					delay_read_reg <= '0' & COUNT_VALUE(9 downto 1);  --half period
               --Define o número de bits para enviar (9 bits -> 8 dados + 1 stop)
					bits_read_reg <= "1001";             --bits left to read
            end if;
         --Senão
			else
				--Define o delay de recepção entre bits
            delay_read_reg <= COUNT_VALUE;          --initialize delay
            --Decrementa a quantidade de bits a receber
				bits_read_reg <= bits_read_reg - 1;     --bits left to read
            --Concatena o bit lido (msb) com o valor do registrador de recepção
				data_read_reg <= uart_read2 & data_read_reg(7 downto 1);
         end if;
      --Senão
		else
			--Decrementa o contador
         delay_read_reg <= delay_read_reg - 1;      --delay
      end if;

      --Control character buffer
		--Se não tem bits para ler e o contador é máximo
      if bits_read_reg = "0000" and delay_read_reg = COUNT_VALUE then
			--Se o nono bit salvo é 0 (flag de ocupado?) ou 
			--(a leitura está habilitada e o 18o bit salvo é 0 (flag de ocupado?))
         if data_save_reg(8) = '0' or 
               (enable_read = '1' and data_save_reg(17) = '0') then
            --Empty buffer
            --Salva o stop bit + o vaor do registrador de recepção?
				data_save_reg(8 downto 0) <= '1' & data_read_reg;
         
			--Senão
			else
            --Second character in buffer
				--Salva o stop bit ( ou flag de ocupado?) + o valor do registrador de recepção como segundo nível do buffer
            data_save_reg(17 downto 9) <= '1' & data_read_reg;
            --Se a leitura está habilitada
				if enable_read = '1' then
					--Copia o 2o byte recebido na 1a posição do buffer
               data_save_reg(8 downto 0) <= data_save_reg(17 downto 9);
            end if;
         end if;
      
		--Senão se a leitura está habilitada
		elsif enable_read = '1' then
         --Limpa a flag de ocupado do bubber posição 2?
			data_save_reg(17) <= '0';                  --data_available
			--Copia o 2o byte recebido na 1a posição do buffer
         data_save_reg(8 downto 0) <= data_save_reg(17 downto 9);
      end if;
   end if;  --rising_edge(clk)

	--Atualiza a saída de transmissão com o lsb do registrador de transmissão
   uart_write <= data_write_reg(0);
	
	--Se ainda tem bits a serem transmitidos
   if bits_write_reg /= "0000" 
-- Comment out the following line for full UART simulation (much slower)
   and log_file = "UNUSED" 
   then
		--Seta a flag de ocupada da transmissão
      busy_write_sig <= '1';
   --Senão
	else
		--Reseta a flag de ocupada da transmissão
      busy_write_sig <= '0';
   end if;
   
	--Atualiza os sinais de saída
	busy_write <= busy_write_sig;
   data_avail <= data_save_reg(8);
   data_out <= data_save_reg(7 downto 0);
   
end process; --uart_proc

-- synthesis_off
   uart_logger:
   if log_file /= "UNUSED" generate
      uart_proc: process(clk, enable_write, data_in)
         file store_file : text open write_mode is log_file;
         variable hex_file_line : line;
         variable c : character;
         variable index : natural;
         variable line_length : natural := 0;
      begin
         if rising_edge(clk) and busy_write_sig = '0' then
            if enable_write = '1' then
               index := conv_integer(data_in(6 downto 0));
               if index /= 10 then
                  c := character'val(index);
                  write(hex_file_line, c);
                  line_length := line_length + 1;
               end if;
               if index = 10 or line_length >= 72 then
--The following line may have to be commented out for synthesis
                  writeline(store_file, hex_file_line);
                  line_length := 0;
               end if;
            end if; --uart_sel
         end if; --rising_edge(clk)
      end process; --uart_proc
   end generate; --uart_logger
-- synthesis_on

end; --architecture logic
