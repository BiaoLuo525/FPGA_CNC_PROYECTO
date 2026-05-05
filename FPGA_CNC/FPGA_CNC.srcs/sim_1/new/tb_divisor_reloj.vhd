----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:46:06
-- Design Name: 
-- Module Name: tb_divisor_reloj - Behavioral
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

entity tb_divisor_reloj is
end entity;

architecture sim of tb_divisor_reloj is
    constant SYS_CLK  : integer := 100000000; -- 100 MHz
    constant BAUD     : integer := 115200;
    
    signal clk        : std_logic := '0';
    signal reset      : std_logic := '1';
    signal tick_uart  : std_logic;
    signal tick_motor : std_logic;

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then report "FAIL: " & message severity error; errors := errors + 1; end if;
    end procedure;

begin
    clk <= not clk after 5 ns;

    dut : entity work.divisor_reloj
        generic map ( CLK_FREQ => SYS_CLK, BAUD_RATE => BAUD, MOTOR_FREQ => 50000 )
        port map ( clk => clk, reset => reset, tick_uart => tick_uart, tick_motor => tick_motor );

    process
        variable errors : integer := 0;
        variable t_start, t_end : time;
    begin
        report "tb_divisor_reloj: Iniciando pruebas";
        wait for 20 ns;
        reset <= '0';

        -- Medimos la frecuencia de los motores (50kHz = 20 us de periodo)
        wait until tick_motor = '1';
        t_start := now;
        wait for 10 ns; -- Soltamos el pulso
        wait until tick_motor = '1';
        t_end := now;

        check((t_end - t_start) = 20 us, "Error: Frecuencia de motores incorrecta", errors);

        if errors = 0 then report "tb_divisor_reloj: PASS"; else report "tb_divisor_reloj: FAIL" severity failure; end if;
        finish;
    end process;
end architecture;
