----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04.05.2026 17:44:44
-- Design Name: 
-- Module Name: top_level - Behavioral
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

entity top_level is
    Generic (
        SYS_CLK_FREQ : integer := 100000000; -- Reloj maestro de la Basys 3 (100 MHz)
        SYS_BAUD     : integer := 115200;    -- Velocidad de comunicación UART
        SYS_MOT_FREQ : integer := 50000      -- Frecuencia de los motores (50 kHz)
    );
    Port ( 
        -- Pines físicos principales
        clk       : in  STD_LOGIC;
        reset     : in  STD_LOGIC;
        
        -- Pines físicos del USB (UART)
        rx        : in  STD_LOGIC;
        tx        : out STD_LOGIC;
        
        -- Pines físicos hacia los motores (PMOD JA y JB)
        step_x    : out STD_LOGIC;
        dir_x     : out STD_LOGIC;
        step_y    : out STD_LOGIC;
        dir_y     : out STD_LOGIC;
        
        -- Pines físicos de Seguridad y Bolígrafo (PMOD JC)
        limit_x   : in  STD_LOGIC;
        limit_y   : in  STD_LOGIC;
        servo_pwm : out STD_LOGIC
    );
end top_level;

architecture Structural of top_level is

    -- ==========================================
    -- 1. DECLARACIÓN DE COMPONENTES
    -- ==========================================
    
    component divisor_reloj
        Generic ( CLK_FREQ : integer; BAUD_RATE : integer; MOTOR_FREQ : integer );
        Port ( clk, reset : in STD_LOGIC; tick_uart, tick_motor : out STD_LOGIC );
    end component;

    component uart_rx
        Generic ( CLK_FREQ : integer; BAUD_RATE : integer );
        Port ( clk, reset, rx : in STD_LOGIC; data_out : out STD_LOGIC_VECTOR(7 downto 0); rx_ready : out STD_LOGIC );
    end component;

    component uart_tx
        Generic ( CLK_FREQ : integer; BAUD_RATE : integer );
        Port ( clk, reset, tx_start : in STD_LOGIC; data_in : in STD_LOGIC_VECTOR(7 downto 0);
               tx, tx_active, tx_done : out STD_LOGIC );
    end component;

    component fsm_main
        Port ( clk, reset : in STD_LOGIC;
               rx_data : in STD_LOGIC_VECTOR(7 downto 0); rx_ready : in STD_LOGIC;
               tx_data : out STD_LOGIC_VECTOR(7 downto 0); tx_start : out STD_LOGIC;
               dir_x, dir_y, pen_state, pen_update : out STD_LOGIC;
               steps_x, steps_y : out STD_LOGIC_VECTOR(15 downto 0);
               start_motion : out STD_LOGIC; motion_done : in STD_LOGIC );
    end component;

    component bresenham_2d
        Port ( clk, reset, tick_motor, start_motion, abort_motion : in STD_LOGIC;
               steps_x, steps_y : in STD_LOGIC_VECTOR(15 downto 0);
               step_x, step_y, motion_done : out STD_LOGIC );
    end component;

    -- El componente de tu amigo para el control del servomotor
    component pen_controller
        Generic ( CLK_FREQ_HZ : positive := 100000000; PWM_HZ : positive := 50; 
                  PULSE_UP_US : positive := 1000; PULSE_DOWN_US : positive := 2000 );
        Port ( clk, reset, update, pen_down_cmd : in std_logic; 
               servo_pwm, pen_is_down : out std_logic );
    end component;

    -- ==========================================
    -- 2. DECLARACIÓN DE "CABLES" INTERNOS
    -- ==========================================
    
    -- Relojes
    signal w_tick_uart   : STD_LOGIC;
    signal w_tick_motor  : STD_LOGIC;
    
    -- UART <-> FSM_Main
    signal w_rx_data     : STD_LOGIC_VECTOR(7 downto 0);
    signal w_rx_ready    : STD_LOGIC;
    signal w_tx_data     : STD_LOGIC_VECTOR(7 downto 0);
    signal w_tx_start    : STD_LOGIC;
    
    -- FSM_Main <-> Bresenham
    signal w_steps_x     : STD_LOGIC_VECTOR(15 downto 0);
    signal w_steps_y     : STD_LOGIC_VECTOR(15 downto 0);
    signal w_start_mot   : STD_LOGIC;
    signal w_motion_done : STD_LOGIC;
    
    -- FSM_Main <-> Pen Controller
    signal w_pen_state   : STD_LOGIC;
    signal w_pen_update  : STD_LOGIC;
    
    -- Seguridad
    signal w_abort_motion : STD_LOGIC;

begin

    -- ==========================================
    -- 3. LÓGICA CONCURRENTE Y "SOLDADURA"
    -- ==========================================

    -- Freno de emergencia: Si CUALQUIER final de carrera se pulsa (limit_x o limit_y), la señal abort se pone a '1'
    w_abort_motion <= limit_x or limit_y;

    Inst_Divisor: divisor_reloj
        generic map ( CLK_FREQ => SYS_CLK_FREQ, BAUD_RATE => SYS_BAUD, MOTOR_FREQ => SYS_MOT_FREQ )
        port map ( clk => clk, reset => reset, tick_uart => w_tick_uart, tick_motor => w_tick_motor );

    Inst_UART_RX: uart_rx
        generic map ( CLK_FREQ => SYS_CLK_FREQ, BAUD_RATE => SYS_BAUD )
        port map ( clk => clk, reset => reset, rx => rx, data_out => w_rx_data, rx_ready => w_rx_ready );

    Inst_UART_TX: uart_tx
        generic map ( CLK_FREQ => SYS_CLK_FREQ, BAUD_RATE => SYS_BAUD )
        port map ( clk => clk, reset => reset, tx_start => w_tx_start, data_in => w_tx_data,
                   tx => tx, tx_active => open, tx_done => open );

    Inst_FSM_Main: fsm_main
        port map (
            clk => clk, reset => reset,
            rx_data => w_rx_data, rx_ready => w_rx_ready,
            tx_data => w_tx_data, tx_start => w_tx_start,
            dir_x => dir_x, dir_y => dir_y, 
            pen_state => w_pen_state, pen_update => w_pen_update,
            steps_x => w_steps_x, steps_y => w_steps_y,
            start_motion => w_start_mot, motion_done => w_motion_done
        );

    Inst_Bresenham: bresenham_2d
        port map (
            clk => clk, reset => reset, tick_motor => w_tick_motor,
            start_motion => w_start_mot, abort_motion => w_abort_motion,
            steps_x => w_steps_x, steps_y => w_steps_y,
            step_x => step_x, step_y => step_y, 
            motion_done => w_motion_done
        );

    Inst_Pen_Controller: pen_controller
        generic map ( CLK_FREQ_HZ => SYS_CLK_FREQ, PWM_HZ => 50, PULSE_UP_US => 1000, PULSE_DOWN_US => 2000 )
        port map (
            clk => clk, reset => reset, update => w_pen_update, pen_down_cmd => w_pen_state,
            servo_pwm => servo_pwm, pen_is_down => open
        );

end Structural;