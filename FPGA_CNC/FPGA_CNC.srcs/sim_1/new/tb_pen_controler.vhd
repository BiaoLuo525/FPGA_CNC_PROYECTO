----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:44:39
-- Design Name: 
-- Module Name: tb_pen_controler - Behavioral
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


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_pen_controller is
end entity;

architecture sim of tb_pen_controller is
    constant CLK_FREQ  : integer := 1000000; -- 1 MHz simulado (1 tick = 1 us)
    constant PWM_HZ    : integer := 500;     -- Acelerado para simular rápido
    
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal update      : std_logic := '0';
    signal pen_down_cmd: std_logic := '0';
    signal servo_pwm   : std_logic;
    
    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then report "FAIL: " & message severity error; errors := errors + 1; end if;
    end procedure;

begin
    clk <= not clk after 500 ns; -- 1 us de periodo

    dut : entity work.pen_controller
        generic map ( CLK_FREQ_HZ => CLK_FREQ, PWM_HZ => PWM_HZ, PULSE_UP_US => 100, PULSE_DOWN_US => 200 )
        port map ( clk => clk, reset => reset, update => update, pen_down_cmd => pen_down_cmd,
                   servo_pwm => servo_pwm, pen_is_down => open );

    process
        variable errors : integer := 0;
        variable t_start, t_end : time;
    begin
        report "tb_pen_controller: Iniciando pruebas";
        wait for 2 us;
        reset <= '0';
        wait for 5 us;

        -- Orden: Bolígrafo Abajo (PULSE_DOWN_US = 200 us en nuestra simulación)
        pen_down_cmd <= '1';
        update <= '1';
        wait for 1 us;
        update <= '0';

        -- Medimos el ancho del pulso PWM
        wait until servo_pwm = '1';
        t_start := now;
        wait until servo_pwm = '0';
        t_end := now;

        -- 200 us equivalen a 200,000 ns
        check((t_end - t_start) = 200 us, "Error: Ancho de pulso PWM incorrecto para Boli Abajo", errors);

        if errors = 0 then report "tb_pen_controller: PASS"; else report "tb_pen_controller: FAIL" severity failure; end if;
        finish;
    end process;
end architecture;