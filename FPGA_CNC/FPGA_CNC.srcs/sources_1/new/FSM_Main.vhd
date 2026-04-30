----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.04.2026 21:57:01
-- Design Name: 
-- Module Name: FSM_Main - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

entity fsm_main is
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;

        -- Interfaz con el Receptor UART (Oídos)
        rx_data      : in  STD_LOGIC_VECTOR(7 downto 0);
        rx_ready     : in  STD_LOGIC;

        -- Interfaz con el Transmisor UART (Boca)
        tx_data      : out STD_LOGIC_VECTOR(7 downto 0);
        tx_start     : out STD_LOGIC;

        -- Interfaz con el Generador de Movimiento (Músculos)
        dir_x        : out STD_LOGIC;
        dir_y        : out STD_LOGIC;
        dir_z        : out STD_LOGIC;
        steps_x      : out STD_LOGIC_VECTOR(15 downto 0);
        steps_y      : out STD_LOGIC_VECTOR(15 downto 0);
        steps_z      : out STD_LOGIC_VECTOR(15 downto 0);
        start_motion : out STD_LOGIC;
        motion_done  : in  STD_LOGIC
    );
end fsm_main;

architecture Behavioral of fsm_main is

    -- Definición de los estados del Cerebro
    type t_State is (s_WAIT_SYNC, s_RECEIVE_PAYLOAD, s_START_MOTION, s_WAIT_MOTION, s_SEND_ACK);
    signal r_State : t_State := s_WAIT_SYNC;

    -- Creamos un Búfer (Array) para guardar los 7 bytes de datos
    type t_Buffer is array (1 to 7) of STD_LOGIC_VECTOR(7 downto 0);
    signal r_rx_buffer : t_Buffer := (others => (others => '0'));
    
    -- Índice para saber qué byte estamos recibiendo
    signal r_byte_index : integer range 1 to 7 := 1;

begin

    process(clk, reset)
    begin
        if reset = '1' then
            r_State      <= s_WAIT_SYNC;
            r_byte_index <= 1;
            tx_start     <= '0';
            start_motion <= '0';
            
            -- Limpiamos las salidas a los motores
            dir_x   <= '0';
            dir_y   <= '0';
            dir_z   <= '0';
            steps_x <= (others => '0');
            steps_y <= (others => '0');
            steps_z <= (others => '0');
            tx_data <= (others => '0');
            
        elsif rising_edge(clk) then
            
            -- Por defecto, estos pulsos están a 0 para que duren solo 1 ciclo de reloj cuando los activemos
            start_motion <= '0';
            tx_start     <= '0';

            case r_State is
                
                -- ESTADO 1: Esperando el byte mágico de Sincronización (0xAA)
                when s_WAIT_SYNC =>
                    if rx_ready = '1' and rx_data = x"AA" then
                        r_byte_index <= 1;
                        r_State      <= s_RECEIVE_PAYLOAD;
                    end if;
                
                -- ESTADO 2: Guardando los siguientes 7 bytes en el búfer
                when s_RECEIVE_PAYLOAD =>
                    if rx_ready = '1' then
                        r_rx_buffer(r_byte_index) <= rx_data;
                        
                        -- ¿Llegó el último byte?
                        if r_byte_index = 7 then
                            r_State <= s_START_MOTION;
                        else
                            r_byte_index <= r_byte_index + 1;
                        end if;
                    end if;

                -- ESTADO 3: Desempaquetar los datos y arrancar los motores
                when s_START_MOTION =>
                    -- Byte 1: Direcciones (Extrayendo bits individuales)
                    dir_x <= r_rx_buffer(1)(0);
                    dir_y <= r_rx_buffer(1)(1);
                    dir_z <= r_rx_buffer(1)(2);
                    
                    -- Concatenar Bytes High y Low para formar números de 16 bits
                    steps_x <= r_rx_buffer(2) & r_rx_buffer(3);
                    steps_y <= r_rx_buffer(4) & r_rx_buffer(5);
                    steps_z <= r_rx_buffer(6) & r_rx_buffer(7);
                    
                    -- Disparamos el pulso de arranque
                    start_motion <= '1'; 
                    r_State      <= s_WAIT_MOTION;

                -- ESTADO 4: Esperar cruzados de brazos a que los motores terminen
                when s_WAIT_MOTION =>
                    if motion_done = '1' then
                        r_State <= s_SEND_ACK;
                    end if;

                -- ESTADO 5: Enviar confirmación a Python ('K' = 0x4B)
                when s_SEND_ACK =>
                    tx_data  <= x"4B"; -- Código ASCII de la letra 'K'
                    tx_start <= '1';   -- Le decimos al Transmisor UART que lo envíe
                    r_State  <= s_WAIT_SYNC; -- Volvemos a empezar
                    
                when others =>
                    r_State <= s_WAIT_SYNC;
                    
            end case;
        end if;
    end process;

end Behavioral;
