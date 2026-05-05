library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pen_controller is
  generic (
    CLK_FREQ_HZ  : positive := 100000000;
    PWM_HZ       : positive := 50;
    PULSE_UP_US  : positive := 1000;
    PULSE_DOWN_US : positive := 2000
  );
  port (
    clk          : in  std_logic;
    reset        : in  std_logic;
    update       : in  std_logic;
    pen_down_cmd : in  std_logic;
    servo_pwm    : out std_logic;
    pen_is_down  : out std_logic
  );
end entity;

architecture rtl of pen_controller is
  constant PERIOD_CLKS : positive := CLK_FREQ_HZ / PWM_HZ;
  constant CLKS_PER_US : positive := CLK_FREQ_HZ / 1000000;
  constant UP_CLKS : natural := CLKS_PER_US * PULSE_UP_US;
  constant DOWN_CLKS : natural := CLKS_PER_US * PULSE_DOWN_US;

  signal pwm_counter : natural range 0 to PERIOD_CLKS := 0;
  signal pulse_width : natural range 0 to PERIOD_CLKS := UP_CLKS;
  signal servo_pwm_reg : std_logic := '0';
  signal pen_is_down_reg : std_logic := '0';
begin
  servo_pwm <= servo_pwm_reg;
  pen_is_down <= pen_is_down_reg;

  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        servo_pwm_reg <= '0';
        pen_is_down_reg <= '0';
        pwm_counter <= 0;
        pulse_width <= UP_CLKS;
      else
        if update = '1' then
          pen_is_down_reg <= pen_down_cmd;
          if pen_down_cmd = '1' then
            pulse_width <= DOWN_CLKS;
          else
            pulse_width <= UP_CLKS;
          end if;
        end if;

        if pwm_counter = PERIOD_CLKS - 1 then
          pwm_counter <= 0;
        else
          pwm_counter <= pwm_counter + 1;
        end if;

        if pwm_counter < pulse_width then
          servo_pwm_reg <= '1';
        else
          servo_pwm_reg <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture;
