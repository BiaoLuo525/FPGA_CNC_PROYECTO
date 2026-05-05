----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.05.2026 20:43:55
-- Design Name: 
-- Module Name: tb_uart_rx - Behavioral
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

entity tb_uart_rx is
end entity;

architecture sim of tb_uart_rx is
    constant CLK_FREQ  : integer := 1000000;
    constant BAUD_RATE : integer := 100000;
    constant BIT_PERIOD: time := 10 us;
    
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal rx          : std_logic := '1';
    signal data_out    : std_logic_vector(7 downto 0);
    signal rx_ready    : std_logic;

    procedure check(condition : boolean; message : string; variable errors : inout integer) is
    begin
        if not condition then report "FAIL: " & message severity error; errors := errors + 1; end if;
    end procedure;

    procedure send_serial_byte(value : std_logic_vector(7 downto 0); signal r_rx: out std_logic) is
    begin
        r_rx <= '0'; -- Start bit
        wait for BIT_PERIOD;
        for i in 0 to 7 loop
            r_rx <= value(i); -- Data bits
            wait for BIT_PERIOD;
        end loop;
        r_rx <= '1'; -- Stop bit
        wait for BIT_PERIOD;
    end procedure;

begin
    clk <= not clk after 500 ns;

    -- Usamos el de tu amigo o el nuestro, asumo que las senales se llaman igual
    dut : entity work.uart_rx
        generic map ( CLK_FREQ => CLK_FREQ, BAUD_RATE => BAUD_RATE)
        port map ( clk => clk, reset => reset, rx => rx, data_out => data_out, rx_ready => rx_ready );

    process
        variable errors : integer := 0;
    begin
        report "tb_uart_rx: Iniciando pruebas";
        wait for 2 us;
        reset <= '0';
        wait for 5 us;

        -- Simulamos que el PC nos envia el byte mágico 0xAA (10101010)
        send_serial_byte(x"AA", rx);

        -- Esperamos a que el módulo nos avise
        wait until rx_ready = '1';
        
        check(data_out = x"AA", "Error: El byte recibido no es correcto", errors);

        if errors = 0 then report "tb_uart_rx: PASS"; else report "tb_uart_rx: FAIL" severity failure; end if;
        finish;
    end process;
end architecture;
