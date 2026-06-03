----------------------------------------------------------------------------------
-- Module Name: FSM_Main - Behavioral
-- Description: Controlador principal con soporte de HOMING (referenciado de origen)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fsm_main is
    Port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;

        -- Interfaz con el Receptor UART
        rx_data      : in  STD_LOGIC_VECTOR(7 downto 0);
        rx_ready     : in  STD_LOGIC;

        -- Interfaz con el Transmisor UART
        tx_data      : out STD_LOGIC_VECTOR(7 downto 0);
        tx_start     : out STD_LOGIC;

        -- Interfaz con Bresenham y el Bolígrafo (PWM)
        dir_x        : out STD_LOGIC;
        dir_y        : out STD_LOGIC;
        pen_state    : out STD_LOGIC;        
        pen_update   : out STD_LOGIC;        
        steps_x      : out STD_LOGIC_VECTOR(15 downto 0);
        steps_y      : out STD_LOGIC_VECTOR(15 downto 0);
        start_motion : out STD_LOGIC;
        motion_done  : in  STD_LOGIC;

        -- Finales de carrera (activo en '1' = ha tocado home)
        limit_x      : in  STD_LOGIC;
        limit_y      : in  STD_LOGIC;
        
        -- NUEVO: Señal para avisar de que estamos en modo Homing
        is_homing    : out STD_LOGIC
    );
end fsm_main;

architecture Behavioral of fsm_main is

    type t_state is (
        IDLE, RECEIVE, CHECK_CRC, EXECUTE, DONE,
        HOME_PEN_UP, HOME_PEN_WAIT, HOME_START_MOVE, HOME_WAIT_LIMITS, HOME_ABORT_MOTION, HOME_SUCCESS, HOME_FAIL
    );
    signal r_state : t_state := IDLE;

    type t_buffer is array (0 to 8) of std_logic_vector(7 downto 0);
    signal r_rx_buffer    : t_buffer := (others => (others => '0'));
    signal r_byte_count   : integer range 0 to 8 := 0;
    signal r_calc_checksum: std_logic_vector(7 downto 0) := (others => '0');

    signal r_home_timeout_x  : std_logic_vector(15 downto 0) := (others => '0');
    signal r_home_timeout_y  : std_logic_vector(15 downto 0) := (others => '0');
    signal r_limit_x_hit     : std_logic := '0';
    signal r_limit_y_hit     : std_logic := '0';
    signal r_homing_request  : std_logic := '0';
    signal r_pen_wait_done   : std_logic := '0';

begin

    process(clk, reset)
    begin
        if reset = '1' then
            r_state          <= IDLE;
            tx_start         <= '0';
            start_motion     <= '0';
            pen_update       <= '0';
            pen_state        <= '0';
            dir_x            <= '0';
            dir_y            <= '0';
            steps_x          <= (others => '0');
            steps_y          <= (others => '0');
            r_limit_x_hit    <= '0';
            r_limit_y_hit    <= '0';
            r_homing_request <= '0';
            r_pen_wait_done  <= '0';
            is_homing        <= '0'; -- Reiniciamos la señal de homing
            
        elsif rising_edge(clk) then

            -- Valores por defecto de pulsos de un ciclo
            tx_start     <= '0';
            pen_update   <= '0';
            start_motion <= '0';
            is_homing    <= '0'; -- Por defecto no estamos haciendo homing

            case r_state is

                when IDLE =>
                    r_byte_count      <= 0;
                    r_calc_checksum   <= x"00";
                    r_limit_x_hit     <= '0';
                    r_limit_y_hit     <= '0';
                    r_homing_request  <= '0';
                    if rx_ready = '1' and rx_data = x"AA" then
                        r_rx_buffer(0) <= rx_data;
                        r_calc_checksum <= x"AA";
                        r_byte_count   <= 1;
                        r_state        <= RECEIVE;
                    end if;

                when RECEIVE =>
                    if rx_ready = '1' then
                        r_rx_buffer(r_byte_count) <= rx_data;
                        if r_byte_count < 8 then
                            r_calc_checksum <= r_calc_checksum xor rx_data;
                        end if;
                        if r_byte_count = 8 then
                            r_state <= CHECK_CRC;
                        else
                            r_byte_count <= r_byte_count + 1;
                        end if;
                    end if;

                when CHECK_CRC =>
                    if r_calc_checksum = r_rx_buffer(8) then
                        if r_rx_buffer(1)(3) = '1' then
                            r_home_timeout_x <= r_rx_buffer(2) & r_rx_buffer(3);
                            r_home_timeout_y <= r_rx_buffer(4) & r_rx_buffer(5);
                            r_homing_request <= '1';
                            r_state          <= HOME_PEN_UP;
                        else
                            dir_x        <= r_rx_buffer(1)(0);
                            dir_y        <= r_rx_buffer(1)(1);
                            pen_state    <= r_rx_buffer(1)(2);
                            steps_x      <= r_rx_buffer(2) & r_rx_buffer(3);
                            steps_y      <= r_rx_buffer(4) & r_rx_buffer(5);
                            pen_update   <= '1';
                            start_motion <= '1';
                            r_state      <= EXECUTE;
                        end if;
                    else
                        tx_data  <= x"45";
                        tx_start <= '1';
                        r_state  <= IDLE;
                    end if;

                when EXECUTE =>
                    if motion_done = '1' then
                        r_state <= DONE;
                    end if;

                when DONE =>
                    tx_data  <= x"4B";
                    tx_start <= '1';
                    r_state  <= IDLE;

                when HOME_PEN_UP =>
                    pen_state      <= '0';
                    pen_update     <= '1';
                    r_pen_wait_done <= '0';
                    r_state        <= HOME_PEN_WAIT;

                when HOME_PEN_WAIT =>
                    r_state <= HOME_START_MOVE;

                when HOME_START_MOVE =>
                    is_homing    <= '1'; -- ¡Avisamos al sistema!
                    dir_x        <= '0';
                    dir_y        <= '0';
                    steps_x      <= r_home_timeout_x;
                    steps_y      <= r_home_timeout_y;
                    start_motion <= '1';
                    r_state      <= HOME_WAIT_LIMITS;

                when HOME_WAIT_LIMITS =>
                    is_homing    <= '1'; -- ¡Mantenemos el aviso durante todo el viaje!
                    
                    if limit_x = '1' then
                        r_limit_x_hit <= '1';
                    end if;
                    if limit_y = '1' then
                        r_limit_y_hit <= '1';
                    end if;

                    if (r_limit_x_hit = '1' or limit_x = '1') and
                       (r_limit_y_hit = '1' or limit_y = '1') then
                        r_state <= HOME_ABORT_MOTION;
                    elsif motion_done = '1' then
                        r_state <= HOME_FAIL;
                    end if;

                when HOME_ABORT_MOTION =>
                    if motion_done = '1' then
                        r_state <= HOME_SUCCESS;
                    end if;

                when HOME_SUCCESS =>
                    tx_data  <= x"48";
                    tx_start <= '1';
                    r_state  <= IDLE;

                when HOME_FAIL =>
                    tx_data  <= x"46";
                    tx_start <= '1';
                    r_state  <= IDLE;

            end case;
        end if;
    end process;

end Behavioral;