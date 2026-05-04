----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04.05.2026 17:47:45
-- Design Name: 
-- Module Name: tb_top_level - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_top_level is
-- Entidad vacía para el testbench
end tb_top_level;

architecture sim of tb_top_level is

    -- Declaración del Top Level
    component top_level
        Generic (
            SYS_CLK_FREQ : integer;
            SYS_BAUD     : integer;
            SYS_MOT_FREQ : integer
        );
        Port ( 
            clk       : in  STD_LOGIC;
            reset     : in  STD_LOGIC;
            rx        : in  STD_LOGIC;
            tx        : out STD_LOGIC;
            step_x    : out STD_LOGIC;
            dir_x     : out STD_LOGIC;
            step_y    : out STD_LOGIC;
            dir_y     : out STD_LOGIC;
            pen_state : out STD_LOGIC
        );
    end component;

    -- Señales de estímulo
    signal clk       : STD_LOGIC := '0';
    signal reset     : STD_LOGIC := '0';
    signal rx        : STD_LOGIC := '1'; -- RX en reposo a '1'
    
    -- Señales de salida a observar
    signal tx        : STD_LOGIC;
    signal step_x    : STD_LOGIC;
    signal dir_x     : STD_LOGIC;
    signal step_y    : STD_LOGIC;
    signal dir_y     : STD_LOGIC;
    signal pen_state : STD_LOGIC;

    -- Tiempos
    constant clk_period : time := 10 ns;      -- 100 MHz
    constant bit_period : time := 8680 ns;    -- 115200 baudios

    -- Procedimiento para inyectar bytes por UART (Como si fuéramos Python)
    procedure UART_WRITE_BYTE (
        i_data_in       : in  STD_LOGIC_VECTOR(7 downto 0);
        signal o_serial : out STD_LOGIC) is
    begin
        o_serial <= '0'; -- Start Bit
        wait for bit_period;
        for ii in 0 to 7 loop
            o_serial <= i_data_in(ii); -- Data Bits
            wait for bit_period;
        end loop;
        o_serial <= '1'; -- Stop Bit
        wait for bit_period;
    end UART_WRITE_BYTE;

begin

    -- Instanciación de nuestro sistema CNC completo
    uut: top_level 
    generic map (
        SYS_CLK_FREQ => 100000000,
        SYS_BAUD     => 115200,
        SYS_MOT_FREQ => 50000      -- Los motores darán pasos cada 20 microsegundos
    )
    port map (
        clk       => clk,
        reset     => reset,
        rx        => rx,
        tx        => tx,
        step_x    => step_x,
        dir_x     => dir_x,
        step_y    => step_y,
        dir_y     => dir_y,
        pen_state => pen_state
    );

    -- Generador del reloj maestro (100 MHz)
    clk_process :process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- Proceso Principal de Pruebas
    stim_proc: process
    begin		
        -- 1. Resetear el sistema al inicio
        reset <= '1';
        wait for 200 ns;	
        reset <= '0';
        wait for 1 us;

        -- 2. ENVIAR PAQUETE DESDE PYTHON: Trazar línea (X=5 pasos, Y=3 pasos)
        
        -- Byte 0: Sincronización
        UART_WRITE_BYTE(x"AA", rx);
        
        -- Byte 1: Direcciones y Estado del Boli (Todo a 0)
        UART_WRITE_BYTE(x"00", rx);
        
        -- Byte 2 y 3: Pasos X (5 pasos -> Hex 0x0005)
        UART_WRITE_BYTE(x"00", rx);
        UART_WRITE_BYTE(x"05", rx);
        
        -- Byte 4 y 5: Pasos Y (3 pasos -> Hex 0x0003)
        UART_WRITE_BYTE(x"00", rx);
        UART_WRITE_BYTE(x"03", rx);
        
        -- Byte 6 y 7: Reservados (Para mantener los 8 bytes de la FSM)
        UART_WRITE_BYTE(x"00", rx);
        UART_WRITE_BYTE(x"00", rx);

        -- 3. Ahora esperamos a que el hardware haga su trabajo
        -- Enviar 8 bytes por UART tarda unos 700 us.
        -- Dar 5 pasos a 50kHz tarda unos 100 us.
        -- Enviar la 'K' de vuelta tarda otros 86 us.
        -- Total esperado: ~900 us. Daremos margen suficiente.
        
        wait for 2 ms; -- (2 milisegundos)

        assert false report "Simulacion Completa. Revisa las ondas de step_x y step_y" severity note;
        wait;
    end process;

end sim;