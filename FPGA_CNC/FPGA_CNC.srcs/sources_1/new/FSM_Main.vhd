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

        -- Interfaz con el Generador de Movimiento (Bresenham) y el Bolígrafo (PWM)
        dir_x        : out STD_LOGIC;
        dir_y        : out STD_LOGIC;
        pen_state    : out STD_LOGIC;        -- 0 = Boli Arriba, 1 = Boli Abajo
        pen_update   : out STD_LOGIC;        -- Pulso para avisar al módulo PWM de un cambio
        steps_x      : out STD_LOGIC_VECTOR(15 downto 0);
        steps_y      : out STD_LOGIC_VECTOR(15 downto 0);
        start_motion : out STD_LOGIC;
        motion_done  : in  STD_LOGIC
    );
end fsm_main;

architecture Behavioral of fsm_main is

    -- Definición de los estados del Cerebro
    type t_State is (s_WAIT_SYNC, s_RECEIVE_PAYLOAD, s_START_MOTION, s_WAIT_MOTION, s_SEND_ACK);
    signal r_State : t_State := s_WAIT_SYNC;

    -- Búfer para guardar los 7 bytes de datos útiles (el de Sync no se guarda)
    type t_Buffer is array (1 to 7) of STD_LOGIC_VECTOR(7 downto 0);
    signal r_rx_buffer : t_Buffer := (others => (others => '0'));
    
    -- Índice para saber qué byte estamos recibiendo
    signal r_byte_index : integer range 1 to 7 := 1;

begin

    process(clk, reset)
        variable v_steps_x : STD_LOGIC_VECTOR(15 downto 0);
        variable v_steps_y : STD_LOGIC_VECTOR(15 downto 0);
    begin
        if reset = '1' then
            r_State      <= s_WAIT_SYNC;
            r_byte_index <= 1;
            tx_start     <= '0';
            start_motion <= '0';
            pen_update   <= '0';
            
            dir_x     <= '0';
            dir_y     <= '0';
            pen_state <= '0'; -- Por defecto, el bolígrafo arranca levantado (arriba)
            steps_x   <= (others => '0');
            steps_y   <= (others => '0');
            tx_data   <= (others => '0');
            
        elsif rising_edge(clk) then
            
            -- Por defecto, estos pulsos duran solo 1 ciclo de reloj
            start_motion <= '0';
            tx_start     <= '0';
            pen_update   <= '0';

            case r_State is
                
                -- ESTADO 1: Esperando el byte de Sincronización (0xAA)
                when s_WAIT_SYNC =>
                    if rx_ready = '1' and rx_data = x"AA" then
                        r_byte_index <= 1;
                        r_State      <= s_RECEIVE_PAYLOAD;
                    end if;
                
                -- ESTADO 2: Guardando los 7 bytes en el búfer
                when s_RECEIVE_PAYLOAD =>
                    if rx_ready = '1' then
                        r_rx_buffer(r_byte_index) <= rx_data;
                        if r_byte_index = 7 then
                            r_State <= s_START_MOTION;
                        else
                            r_byte_index <= r_byte_index + 1;
                        end if;
                    end if;

                -- ESTADO 3: Desempaquetar y decidir qué hacer
                when s_START_MOTION =>
                    -- Byte 1: Extrayendo bits (Bit 0 = Dir X, Bit 1 = Dir Y, Bit 2 = Estado Boli)
                    dir_x     <= r_rx_buffer(1)(0);
                    dir_y     <= r_rx_buffer(1)(1);
                    pen_state <= r_rx_buffer(1)(2); 
                    
                    -- Disparamos la actualización del servomotor
                    pen_update <= '1';
                    
                    -- Concatenar Bytes Altos y Bajos para formar los números de 16 bits de X e Y
                    v_steps_x := r_rx_buffer(2) & r_rx_buffer(3);
                    v_steps_y := r_rx_buffer(4) & r_rx_buffer(5);
                    
                    steps_x <= v_steps_x;
                    steps_y <= v_steps_y;
                    
                    -- Lógica inteligente del Plotter:
                    -- Si Python dice que nos movamos 0 pasos, es que solo quería subir/bajar el bolígrafo.
                    if v_steps_x = x"0000" and v_steps_y = x"0000" then
                        r_State <= s_SEND_ACK; -- Saltamos directamente a la confirmación
                    else
                        start_motion <= '1';   -- Arrancamos los motores X e Y
                        r_State      <= s_WAIT_MOTION;
                    end if;

                -- ESTADO 4: Esperar a que el módulo de Bresenham termine su trabajo
                when s_WAIT_MOTION =>
                    if motion_done = '1' then
                        r_State <= s_SEND_ACK;
                    end if;

                -- ESTADO 5: Enviar confirmación ('K' = 0x4B) a Python
                when s_SEND_ACK =>
                    tx_data  <= x"4B"; 
                    tx_start <= '1';   
                    r_State  <= s_WAIT_SYNC; -- Volvemos a esperar la siguiente instrucción
                    
                when others =>
                    r_State <= s_WAIT_SYNC;
                    
            end case;
        end if;
    end process;

end Behavioral;