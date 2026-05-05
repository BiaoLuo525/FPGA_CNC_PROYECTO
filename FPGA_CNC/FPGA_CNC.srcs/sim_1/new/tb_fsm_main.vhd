----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:41:55
-- Design Name: 
-- Module Name: tb_fsm_main - Behavioral
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

entity tb_fsm_main is
end entity;

architecture sim of tb_fsm_main is
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '1';
    signal rx_data      : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_ready     : std_logic := '0';
    signal tx_data      : std_logic_vector(7 downto 0);
    signal tx_start     : std_logic;
    signal dir_x, dir_y : std_logic;
    signal pen_state    : std_logic;
    signal pen_update   : std_logic;
    signal steps_x      : std_logic_vector(15 downto 0);
    signal steps_y      : std_logic_vector(15 downto 0);
    signal start_motion : std_logic;
    signal motion_done  : std_logic := '0';

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then
            report "FAIL: " & message severity error;
            errors := errors + 1;
        end if;
    end procedure;

    procedure send_byte(data : std_logic_vector(7 downto 0); signal r_data: out std_logic_vector; signal r_ready: out std_logic) is
    begin
        r_data <= data;
        r_ready <= '1';
        wait for 10 ns;
        r_ready <= '0';
        wait for 40 ns;
    end procedure;

begin
    clk <= not clk after 5 ns;

    dut : entity work.fsm_main
        port map (
            clk => clk, reset => reset, rx_data => rx_data, rx_ready => rx_ready,
            tx_data => tx_data, tx_start => tx_start, dir_x => dir_x, dir_y => dir_y,
            pen_state => pen_state, pen_update => pen_update, steps_x => steps_x, steps_y => steps_y,
            start_motion => start_motion, motion_done => motion_done
        );

    process
        variable errors : integer := 0;
    begin
        report "tb_fsm_main: Iniciando pruebas";
        wait for 50 ns;
        reset <= '0';
        wait for 50 ns;

        -- Enviamos paquete: Sync(AA), Config(05 -> X_dir=1, Y_dir=0, Pen=1), X(000A), Y(000B), Z/Res(0000)
        send_byte(x"AA", rx_data, rx_ready);
        send_byte(x"05", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready);
        send_byte(x"0A", rx_data, rx_ready); -- X = 10
        send_byte(x"00", rx_data, rx_ready);
        send_byte(x"0B", rx_data, rx_ready); -- Y = 11
        send_byte(x"00", rx_data, rx_ready);
        send_byte(x"00", rx_data, rx_ready);

        wait until start_motion = '1';
        
        -- Verificaciones
        check(dir_x = '1', "Error: dir_x incorrecto", errors);
        check(dir_y = '0', "Error: dir_y incorrecto", errors);
        check(pen_state = '1', "Error: pen_state incorrecto", errors);
        check(to_integer(unsigned(steps_x)) = 10, "Error: steps_x incorrecto", errors);
        check(to_integer(unsigned(steps_y)) = 11, "Error: steps_y incorrecto", errors);
        check(pen_update = '1', "Error: No se actualizo el boli", errors);

        -- Simulamos que los motores terminaron
        wait for 50 ns;
        motion_done <= '1';
        wait for 10 ns;
        motion_done <= '0';

        wait until tx_start = '1';
        check(tx_data = x"4B", "Error: No devolvio la letra K (0x4B)", errors);

        if errors = 0 then
            report "tb_fsm_main: PASS";
        else
            report "tb_fsm_main: FAIL con " & integer'image(errors) & " errores" severity failure;
        end if;
        finish;
    end process;
end architecture;
