----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:42:59
-- Design Name: 
-- Module Name: tb_uart_tx - Behavioral
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

entity tb_uart_tx is
end entity;

architecture sim of tb_uart_tx is
    constant CLK_FREQ  : integer := 1000000; -- 1 MHz simulado
    constant BAUD_RATE : integer := 100000;  -- 100 kHz simulado
    constant BIT_PERIOD: time := 10 us;      -- 1 / 100kHz
    
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal tx_start    : std_logic := '0';
    signal data_in     : std_logic_vector(7 downto 0) := (others => '0');
    signal tx          : std_logic;
    signal tx_done     : std_logic;

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then report "FAIL: " & message severity error; errors := errors + 1; end if;
    end procedure;

begin
    clk <= not clk after 500 ns;

    dut : entity work.uart_tx
        generic map ( CLK_FREQ => CLK_FREQ, BAUD_RATE => BAUD_RATE )
        port map ( clk => clk, reset => reset, tx_start => tx_start, data_in => data_in,
                   tx => tx, tx_active => open, tx_done => tx_done );

    process
        variable errors : integer := 0;
    begin
        report "tb_uart_tx: Iniciando pruebas";
        wait for 2 us;
        reset <= '0';
        wait for 5 us;

        -- Mandamos enviar 0x5A (Binario: 01011010)
        data_in <= x"5A";
        tx_start <= '1';
        wait for 1 us;
        tx_start <= '0';

        -- Comprobamos Start Bit
        wait until tx = '0';
        wait for BIT_PERIOD / 2; -- Nos situamos en el centro del bit
        check(tx = '0', "Error en Start Bit", errors);

        -- Comprobamos los 8 bits de datos (LSB primero)
        for i in 0 to 7 loop
            wait for BIT_PERIOD;
            check(tx = data_in(i), "Error en Bit de datos " & integer'image(i), errors);
        end loop;

        -- Comprobamos Stop Bit
        wait for BIT_PERIOD;
        check(tx = '1', "Error en Stop Bit", errors);

        -- Comprobamos pulso de finalización
        wait until tx_done = '1';
        check(tx_done = '1', "Error: tx_done no se activo", errors);

        if errors = 0 then report "tb_uart_tx: PASS"; else report "tb_uart_tx: FAIL" severity failure; end if;
        finish;
    end process;
end architecture;
