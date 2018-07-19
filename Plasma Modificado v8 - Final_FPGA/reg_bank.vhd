---------------------------------------------------------------------
-- TITLE: Register Bank
-- AUTHOR: Steve Rhoads (rhoadss@yahoo.com)
-- DATE CREATED: 2/2/01
-- FILENAME: reg_bank.vhd
-- PROJECT: Plasma CPU core
-- COPYRIGHT: Software placed into the public domain by the author.
--    Software 'as is' without warranty.  Author liable for nothing.
-- DESCRIPTION:
--    Implements a register bank with 32 registers that are 32-bits wide.
--    There are two read-ports and one write port.

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- ANALISADO: 9/7/16
-- MODIFICADO: 30/11/16 - Substitui use work.mlite_pack.all;
--	por use work.mlite_pack_mod.all;
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.mlite_pack_mod.all;
--library UNISIM;               --May need to uncomment for ModelSim
--use UNISIM.vcomponents.all;   --May need to uncomment for ModelSim

entity reg_bank is
   generic(memory_type : string := "XILINX_16X");
   port(clk            : in  std_logic;
        reset_in       : in  std_logic;
        pause          : in  std_logic;
        rs_index       : in  std_logic_vector(5 downto 0);	--End. fonte de dados (6 bits ao invés de 5)
        rt_index       : in  std_logic_vector(5 downto 0);	--End. fonte de ou destino de dados
        rd_index       : in  std_logic_vector(5 downto 0);	--End. destino de dados
        reg_source_out : out std_logic_vector(31 downto 0);	--Saída de dados de acordo com rs
        reg_target_out : out std_logic_vector(31 downto 0);	--Saída de dados de acordo com rt
        reg_dest_new   : in  std_logic_vector(31 downto 0);	--Entrada de dados de acordo com rd
        intr_enable    : out std_logic);							--Flag de enable de interrupção
end; --entity reg_bank

--------------------------------------------------------------------
-- The ram_block architecture attempts to use TWO dual-port memories.
-- Different FPGAs and ASICs need different implementations.
-- Choose one of the RAM implementations below.
-- I need feedback on this section!
--------------------------------------------------------------------

--Pelo que entendi o 6o bit do endereçamento define se é um registrador da CPU (0)
--ou do coprocessador 0 (1)

architecture ram_block of reg_bank is
   signal intr_enable_reg : std_logic;		--Flag Interrupt Enable (coprocessor 0, reg. Status, end. 12 bit 0)
   type ram_type is array(31 downto 0) of std_logic_vector(31 downto 0);	--Vetor com 32 posições de 32 bits
   
   --controls access to dual-port memories
   signal addr_read1, addr_read2 : std_logic_vector(4 downto 0);
   signal addr_write             : std_logic_vector(4 downto 0);
   signal data_out1, data_out2   : std_logic_vector(31 downto 0);
   signal write_enable           : std_logic;

begin

--Processo sensível a todos os ports e sinais  
reg_proc: process(clk, rs_index, rt_index, rd_index, reg_dest_new, 
      intr_enable_reg, data_out1, data_out2, reset_in, pause)
begin
   --setup for first dual-port memory
   if rs_index = "101110" then  --reg_epc CP0 14	--Valores superiores a 31 (11111b) não fazem parte 
																	--dos registradores da CPU
																	--Esse registrador armazena o end. da instrução
																	--que gerou uma exceção (coprocessador 0).
      addr_read1 <= "00000";					--End = 0
   else
      addr_read1 <= rs_index(4 downto 0);	--End = 5 lsbs de rs
   end if;
	
	--Verifica o valor de rs
   case rs_index is
   when "000000" => reg_source_out <= ZERO;											--Retorna 0
   
	--Parte da CPU chamada de coprocessor 0
	--End. 12=Ch=1100b representa o registrador Status, onde o bit 0 é o enable das interrupções
	when "101100" => reg_source_out <= ZERO(31 downto 1) & intr_enable_reg;	--Retorna stado da interrupção
							  --interrupt vector address = 0x3c								
   when "111111" => reg_source_out <= ZERO(31 downto 8) & "00111100";		--Retorna o endereço do vetor 
																									--de interrupções
   when others   => reg_source_out <= data_out1;									--Retorna data_out1, valor lido
																									--da memória lpm_ram_dp_component1	
   end case;

   --setup for second dual-port memory
   addr_read2 <= rt_index(4 downto 0);		--End = 5 lsbs de rt
   
	--Verifica o valor de rt
	case rt_index is
   when "000000" => reg_target_out <= ZERO;											--Retorna 0
   when others   => reg_target_out <= data_out2;									--Retorna data_out2, valor lido
																									--da memória lpm_ram_dp_component2
   end case;

	--Verifica as condições para escrever em rd
   --setup write port for both dual-port memories
   --Se não é o reg. $zero da CPU nem o reg. Status do coprocessador 0 e não está pausado
	if rd_index /= "000000" and rd_index /= "101100" and pause = '0' then
      write_enable <= '1';
   else
      write_enable <= '0';
   end if;
	
	--Se é o reg. EPC do coprocessador 0
   if rd_index = "101110" then  --reg_epc CP0 14
      addr_write <= "00000";
   else
      addr_write <= rd_index(4 downto 0);		--End = 5 lsbs de rd
   end if;

	--Condição de reset
   if reset_in = '1' then
      intr_enable_reg <= '0';						--Interrupções são desabilitadas
   
	--Condição de borda de subida no clock
	elsif rising_edge(clk) then
      --Se é o reg. EPC do coprocessador 0
		if rd_index = "101110" then     --reg_epc CP0 14
         intr_enable_reg <= '0';      			--Interrupções são desabilitadas
      
		--Se é o reg. Status do coprocessador 0
		elsif rd_index = "101100" then
         intr_enable_reg <= reg_dest_new(0);	--Altera o estado das interrupção (enable/disable)
      end if;
   end if;

	--Atualiza o estado da flag que aparentemente sinaliza se as interrupções então ou não estão habilitadas
   intr_enable <= intr_enable_reg;
end process;


--------------------------------------------------------------
---- Pick only ONE of the dual-port RAM implementations below!
--------------------------------------------------------------

   -- Option #1
   -- One tri-port RAM, two read-ports, one write-port
   -- 32 registers 32-bits wide
   tri_port_mem:
   if memory_type = "TRI_PORT_X" generate
      ram_proc: process(clk, addr_read1, addr_read2, 
            addr_write, reg_dest_new, write_enable)
      variable tri_port_ram : ram_type := (others => ZERO);
      begin
         data_out1 <= tri_port_ram(conv_integer(addr_read1));
         data_out2 <= tri_port_ram(conv_integer(addr_read2));
         if rising_edge(clk) then
            if write_enable = '1' then
               tri_port_ram(conv_integer(addr_write)) := reg_dest_new;
            end if;
         end if;
      end process;
   end generate; --tri_port_mem


   -- Option #2
   -- Two dual-port RAMs, each with one read-port and one write-port
   dual_port_mem:
   if memory_type = "DUAL_PORT_" generate
      ram_proc2: process(clk, addr_read1, addr_read2, 
            addr_write, reg_dest_new, write_enable)
      variable dual_port_ram1 : ram_type := (others => ZERO);
      variable dual_port_ram2 : ram_type := (others => ZERO);
      begin
         data_out1 <= dual_port_ram1(conv_integer(addr_read1));
         data_out2 <= dual_port_ram2(conv_integer(addr_read2));
         if rising_edge(clk) then
            if write_enable = '1' then
               dual_port_ram1(conv_integer(addr_write)) := reg_dest_new;
               dual_port_ram2(conv_integer(addr_write)) := reg_dest_new;
            end if;
         end if;
      end process;
   end generate; --dual_port_mem


   -- Option #3
   -- RAM16X1D: 16 x 1 positive edge write, asynchronous read dual-port 
   -- distributed RAM for all Xilinx FPGAs
   -- From library UNISIM; use UNISIM.vcomponents.all;
   xilinx_16x1d:
   if memory_type = "XILINX_16X" generate
      signal data_out1A, data_out1B : std_logic_vector(31 downto 0);
      signal data_out2A, data_out2B : std_logic_vector(31 downto 0);
      signal weA, weB               : std_logic;
      signal no_connect             : std_logic_vector(127 downto 0);
   begin
      weA <= write_enable and not addr_write(4);  --lower 16 registers
      weB <= write_enable and addr_write(4);      --upper 16 registers
      
      reg_loop: for i in 0 to 31 generate
      begin
         --Read port 1 lower 16 registers
         reg_bit1a : RAM16X1D
         port map (
            WCLK  => clk,              -- Port A write clock input
            WE    => weA,              -- Port A write enable input
            A0    => addr_write(0),    -- Port A address[0] input bit
            A1    => addr_write(1),    -- Port A address[1] input bit
            A2    => addr_write(2),    -- Port A address[2] input bit
            A3    => addr_write(3),    -- Port A address[3] input bit
            D     => reg_dest_new(i),  -- Port A 1-bit data input
            DPRA0 => addr_read1(0),    -- Port B address[0] input bit
            DPRA1 => addr_read1(1),    -- Port B address[1] input bit
            DPRA2 => addr_read1(2),    -- Port B address[2] input bit
            DPRA3 => addr_read1(3),    -- Port B address[3] input bit
            DPO   => data_out1A(i),    -- Port B 1-bit data output
            SPO   => no_connect(i)     -- Port A 1-bit data output
         );
         --Read port 1 upper 16 registers
         reg_bit1b : RAM16X1D
         port map (
            WCLK  => clk,              -- Port A write clock input
            WE    => weB,              -- Port A write enable input
            A0    => addr_write(0),    -- Port A address[0] input bit
            A1    => addr_write(1),    -- Port A address[1] input bit
            A2    => addr_write(2),    -- Port A address[2] input bit
            A3    => addr_write(3),    -- Port A address[3] input bit
            D     => reg_dest_new(i),  -- Port A 1-bit data input
            DPRA0 => addr_read1(0),    -- Port B address[0] input bit
            DPRA1 => addr_read1(1),    -- Port B address[1] input bit
            DPRA2 => addr_read1(2),    -- Port B address[2] input bit
            DPRA3 => addr_read1(3),    -- Port B address[3] input bit
            DPO   => data_out1B(i),    -- Port B 1-bit data output
            SPO   => no_connect(32+i)  -- Port A 1-bit data output
         );
         --Read port 2 lower 16 registers
         reg_bit2a : RAM16X1D
         port map (
            WCLK  => clk,              -- Port A write clock input
            WE    => weA,              -- Port A write enable input
            A0    => addr_write(0),    -- Port A address[0] input bit
            A1    => addr_write(1),    -- Port A address[1] input bit
            A2    => addr_write(2),    -- Port A address[2] input bit
            A3    => addr_write(3),    -- Port A address[3] input bit
            D     => reg_dest_new(i),  -- Port A 1-bit data input
            DPRA0 => addr_read2(0),    -- Port B address[0] input bit
            DPRA1 => addr_read2(1),    -- Port B address[1] input bit
            DPRA2 => addr_read2(2),    -- Port B address[2] input bit
            DPRA3 => addr_read2(3),    -- Port B address[3] input bit
            DPO   => data_out2A(i),    -- Port B 1-bit data output
            SPO   => no_connect(64+i)  -- Port A 1-bit data output
         );
         --Read port 2 upper 16 registers
         reg_bit2b : RAM16X1D
         port map (
            WCLK  => clk,              -- Port A write clock input
            WE    => weB,              -- Port A write enable input
            A0    => addr_write(0),    -- Port A address[0] input bit
            A1    => addr_write(1),    -- Port A address[1] input bit
            A2    => addr_write(2),    -- Port A address[2] input bit
            A3    => addr_write(3),    -- Port A address[3] input bit
            D     => reg_dest_new(i),  -- Port A 1-bit data input
            DPRA0 => addr_read2(0),    -- Port B address[0] input bit
            DPRA1 => addr_read2(1),    -- Port B address[1] input bit
            DPRA2 => addr_read2(2),    -- Port B address[2] input bit
            DPRA3 => addr_read2(3),    -- Port B address[3] input bit
            DPO   => data_out2B(i),    -- Port B 1-bit data output
            SPO   => no_connect(96+i)  -- Port A 1-bit data output
         );
      end generate; --reg_loop

      data_out1 <= data_out1A when addr_read1(4)='0' else data_out1B;
      data_out2 <= data_out2A when addr_read2(4)='0' else data_out2B;
   end generate; --xilinx_16x1d


   -- Option #4
   -- RAM32X1D: 32 x 1 positive edge write, asynchronous read dual-port 
   -- distributed RAM for 5-LUT Xilinx FPGAs such as Virtex-5
   -- From library UNISIM; use UNISIM.vcomponents.all;
   xilinx_32x1d:
   if memory_type = "XILINX_32X" generate
      signal no_connect             : std_logic_vector(63 downto 0);
   begin
      reg_loop: for i in 0 to 31 generate
      begin
         --Read port 1
         reg_bit1 : RAM32X1D
         port map (
            WCLK  => clk,              -- Port A write clock input
            WE    => write_enable,     -- Port A write enable input
            A0    => addr_write(0),    -- Port A address[0] input bit
            A1    => addr_write(1),    -- Port A address[1] input bit
            A2    => addr_write(2),    -- Port A address[2] input bit
            A3    => addr_write(3),    -- Port A address[3] input bit
            A4    => addr_write(4),    -- Port A address[4] input bit
            D     => reg_dest_new(i),  -- Port A 1-bit data input
            DPRA0 => addr_read1(0),    -- Port B address[0] input bit
            DPRA1 => addr_read1(1),    -- Port B address[1] input bit
            DPRA2 => addr_read1(2),    -- Port B address[2] input bit
            DPRA3 => addr_read1(3),    -- Port B address[3] input bit
            DPRA4 => addr_read1(4),    -- Port B address[4] input bit
            DPO   => data_out1(i),     -- Port B 1-bit data output
            SPO   => no_connect(i)     -- Port A 1-bit data output
         );
         --Read port 2
         reg_bit2 : RAM32X1D
         port map (
            WCLK  => clk,              -- Port A write clock input
            WE    => write_enable,     -- Port A write enable input
            A0    => addr_write(0),    -- Port A address[0] input bit
            A1    => addr_write(1),    -- Port A address[1] input bit
            A2    => addr_write(2),    -- Port A address[2] input bit
            A3    => addr_write(3),    -- Port A address[3] input bit
            A4    => addr_write(4),    -- Port A address[4] input bit
            D     => reg_dest_new(i),  -- Port A 1-bit data input
            DPRA0 => addr_read2(0),    -- Port B address[0] input bit
            DPRA1 => addr_read2(1),    -- Port B address[1] input bit
            DPRA2 => addr_read2(2),    -- Port B address[2] input bit
            DPRA3 => addr_read2(3),    -- Port B address[3] input bit
            DPRA4 => addr_read2(4),    -- Port B address[4] input bit
            DPO   => data_out2(i),     -- Port B 1-bit data output
            SPO   => no_connect(32+i)  -- Port A 1-bit data output
         );
      end generate; --reg_loop
   end generate; --xilinx_32x1d


   -- Option #5
   -- Altera LPM_RAM_DP
   altera_mem:
   if memory_type = "ALTERA_LPM" generate		--Aparentemente é essa opções da memória que sintetisei
      signal clk_delayed : std_logic;
      signal addr_reg    : std_logic_vector(4 downto 0);
      signal data_reg    : std_logic_vector(31 downto 0);
      signal q1          : std_logic_vector(31 downto 0);
      signal q2          : std_logic_vector(31 downto 0);
   begin
      -- Altera dual port RAMs must have the addresses registered (sampled
      -- at the rising edge).  This is very unfortunate.
      -- Therefore, the dual port RAM read clock must delayed so that
      -- the read address signal can be sent from the mem_ctrl block.
      -- This solution also delays the how fast the registers are read so the 
      -- maximum clock speed is cut in half (12.5 MHz instead of 25 MHz).

		--Cria uma sinal de clock invertido para as memórias
		--Isso permite a leitura ou escrita na borda de descida
		
      clk_delayed <= not clk;  --Could be delayed by 1/4 clock cycle instead
      
		dpram_bypass: process(clk, addr_write, reg_dest_new, write_enable)
      begin
			--Se for uma operação de escrita
			--Lê o endereço e dados a serem garavados na borda de subida do clk (e grava na de descida!)
         if rising_edge(clk) and write_enable = '1' then
            
				--Pega o endereço pré definaido (vide condições para escrever em rd)
				addr_reg <= addr_write;
				
				--Pega o valor a ser gravado
            data_reg <= reg_dest_new;
				
         end if;
      end process; --dpram_bypass

		--Define o valor de data_out1 e data_out2
      -- Bypass dpram if reading what was just written (Altera limitation)
		
		--q1 e q2 quando addr_read1e2 != addr_reg (endereço de leitura != do de gravação)
		--senão os dados são definidos com o valor que está sendo escrito,
		--isso quer dizer: first write, after read
      data_out1 <= q1 when addr_read1 /= addr_reg else data_reg;
      data_out2 <= q2 when addr_read2 /= addr_reg else data_reg;
      
      --Declara uma Megafunction LPM para criar a memória
		lpm_ram_dp_component1 : lpm_ram_dp
      generic map (
         LPM_WIDTH => 32,
         LPM_WIDTHAD => 5,
         --LPM_NUMWORDS => 0,
         LPM_INDATA => "REGISTERED",
         LPM_OUTDATA => "UNREGISTERED",
         LPM_RDADDRESS_CONTROL => "REGISTERED",
         LPM_WRADDRESS_CONTROL => "REGISTERED",
         LPM_FILE => "UNUSED",
         LPM_TYPE => "LPM_RAM_DP",
         USE_EAB  => "ON",
         INTENDED_DEVICE_FAMILY => "UNUSED",
         RDEN_USED => "FALSE",
         LPM_HINT => "UNUSED")
      port map (
         RDCLOCK   => clk_delayed,
         RDCLKEN   => '1',
         RDADDRESS => addr_read1,		--<-- diferença entre as funções
         RDEN      => '1',
         DATA      => reg_dest_new,
         WRADDRESS => addr_write,
         WREN      => write_enable,
         WRCLOCK   => clk,
         WRCLKEN   => '1',
         Q         => q1);					--<-- diferença entre as funções
      
		--Declara outra Megafunction LPM para criar a memória
		lpm_ram_dp_component2 : lpm_ram_dp
      generic map (
         LPM_WIDTH => 32,
         LPM_WIDTHAD => 5,
         --LPM_NUMWORDS => 0,
         LPM_INDATA => "REGISTERED",
         LPM_OUTDATA => "UNREGISTERED",
         LPM_RDADDRESS_CONTROL => "REGISTERED",
         LPM_WRADDRESS_CONTROL => "REGISTERED",
         LPM_FILE => "UNUSED",
         LPM_TYPE => "LPM_RAM_DP",
         USE_EAB  => "ON",
         INTENDED_DEVICE_FAMILY => "UNUSED",
         RDEN_USED => "FALSE",
         LPM_HINT => "UNUSED")
      port map (
         RDCLOCK   => clk_delayed,
         RDCLKEN   => '1',
         RDADDRESS => addr_read2,	--<-- diferença entre as funções
         RDEN      => '1',
         DATA      => reg_dest_new,
         WRADDRESS => addr_write,
         WREN      => write_enable,
         WRCLOCK   => clk,
         WRCLKEN   => '1',
         Q         => q2);				--<-- diferença entre as funções
			
			--Pelo que estou entendendo são duas memórias paralelas que são lidas separadamente porém,
			--quando ocorre uma gravação, as duas recebem o mesmo valor nos mesmos endereços.
			--Essa deve ter sido a saída para fazer uma memória com três portas (2 read, 1 write).
			
   end generate; --altera_mem

end; --architecture ram_block
