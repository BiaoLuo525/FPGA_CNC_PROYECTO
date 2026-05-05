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


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_top_level is
end entity;

architecture sim of tb_top_level is
    constant SYS_CLK_FREQ : integer := 1000000; -- Acelerado para simulación
    constant SYS_BAUD     : integer := 100000;
    constant CLKS_PER_BIT : integer := SYS_CLK_FREQ / SYS_BAUD;

    signal clk       : std_logic := '0';
    signal reset     : std_logic := '1';
    signal rx        : std_logic := '1';
    signal tx        : std_logic;
    signal step_x    : std_logic;
    signal dir_x     : std_logic;
    signal step_y    : std_logic;
    signal dir_y     : std_logic;
    signal limit_x   : std_logic := '0';
    signal limit_y   : std_logic := '0';
    signal servo_pwm : std_logic;
    
    signal count_x   : integer := 0;

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then
            report "FAIL: " & message severity error;
            errors := errors + 1;
        end if;
    end procedure;

begin
    clk <= not clk after 500 ns; -- 1 MHz simulado

    dut : entity work.top_level
        generic map ( SYS_CLK_FREQ => SYS_CLK_FREQ, SYS_BAUD => SYS_BAUD, SYS_MOT_FREQ => 50000 )
        port map (
            clk => clk, reset => reset, rx => rx, tx => tx,
            step_x => step_x, dir_x => dir_x, step_y => step_y, dir_y => dir_y,
            limit_x => limit_x, limit_y => limit_y, servo_pwm => servo_pwm
        );

    -- Cuenta pasos reales en los pines de salida
    process(clk)
    begin
        if falling_edge(clk) then
            if reset = '0' and step_x = '1' then
                count_x <= count_x + 1;
            end if;
        end if;
    end process;

    process
        variable errors : integer := 0;
        
        procedure uart_send_byte(value : std_logic_vector(7 downto 0)) is
        begin
            rx <= '0'; -- Start
            for i in 1 to CLKS_PER_BIT loop wait until rising_edge(clk); end loop;
            for bit_index in 0 to 7 loop
                rx <= value(bit_index);
                for i in 1 to CLKS_PER_BIT loop wait until rising_edge(clk); end loop;
            end loop;
            rx <= '1'; -- Stop
            for i in 1 to CLKS_PER_BIT loop wait until rising_edge(clk); end loop;
        end procedure;

    begin
        report "tb_top_level: Iniciando pruebas de integracion...";
        wait for 2 us;
        reset <= '0';
        wait for 10 us;

        -- Enviamos el paquete completo por UART serial
        -- Paquete: Sync, Config(DirX=1), X=5, Y=0, Res=0
        uart_send_byte(x"AA");
        uart_send_byte(x"01");
        uart_send_byte(x"00");
        uart_send_byte(x"05");
        uart_send_byte(x"00");
        uart_send_byte(x"00");
        uart_send_byte(x"00");
        uart_send_byte(x"00");

        -- Esperamos a que la FSM procese y el motor dé los 5 pasos
        wait for 3 ms;

        check(count_x = 5, "TopLevel: No dio los 5 pasos ordenados", errors);
        check(dir_x = '1', "TopLevel: Direccion X incorrecta", errors);

        if errors = 0 then
            report "tb_top_level: PASS TODO CORRECTO";
        else
            report "tb_top_level: FAIL con " & integer'image(errors) & " errores" severity failure;
        end if;
        finish;
    end process;
end architecture;