I2C_ID = 0
SDA = 4
SCL = 5

-- Device I2C Address
LCD_ADDRESS = 0x3e
RGB_ADDRESS = 0x62

-- color define
WHITE = 0
RED = 1
GREEN = 2
BLUE = 3

REG_RED = 0x04        -- pwm2
REG_GREEN = 0x03        -- pwm1
REG_BLUE = 0x02        -- pwm0

REG_MODE1 = 0x00
REG_MODE2 = 0x01
REG_OUTPUT = 0x08

-- commands
LCD_CLEARDISPLAY = 0x01
LCD_RETURNHOME = 0x02
LCD_ENTRYMODESET = 0x04
LCD_DISPLAYCONTROL = 0x08
LCD_CURSORSHIFT = 0x10
LCD_FUNCTIONSET = 0x20
LCD_SETCGRAMADDR = 0x40
LCD_SETDDRAMADDR = 0x80

-- flags for display entry mode
LCD_ENTRYRIGHT = 0x00
LCD_ENTRYLEFT = 0x02
LCD_ENTRYSHIFTINCREMENT = 0x01
LCD_ENTRYSHIFTDECREMENT = 0x00

-- flags for display on/off control
LCD_DISPLAYON = 0x04
LCD_DISPLAYOFF = 0x00
LCD_CURSORON = 0x02
LCD_CURSOROFF = 0x00
LCD_BLINKON = 0x01
LCD_BLINKOFF = 0x00

-- flags for display/cursor shift
LCD_DISPLAYMOVE = 0x08
LCD_CURSORMOVE = 0x00
LCD_MOVERIGHT = 0x04
LCD_MOVELEFT = 0x00

-- flags for function set
LCD_8BITMODE = 0x10
LCD_4BITMODE = 0x00
LCD_2LINE = 0x08
LCD_1LINE = 0x00
LCD_5x10DOTS = 0x04
LCD_5x8DOTS = 0x00

display_function = 0
display_control = 0
display_mode = 0

local bor, band, bnot = bit.bor, bit.band, bit.bnot


--OK
local function i2c_send_bytes(data)
  i2c.start(I2C_ID)
  i2c.address(I2C_ID, LCD_ADDRESS, i2c.TRANSMITTER)
  i2c.write(I2C_ID, data)
  i2c.stop(I2C_ID)
end

--OK
local function write(value)
  i2c_send_bytes({0x40, value})
end

--OK
local function set_cursor(col, row)
  col = (row == 0) and bor(col, 0x80) or bor(col, 0xC0)
  i2c_send_bytes({0x80, col})
end

--OK
local function command(value)
  i2c_send_bytes({0x80, value})
end

--OK
local function set_reg(addr, data)
  i2c.start(I2C_ID)
  i2c.address(I2C_ID, RGB_ADDRESS, i2c.TRANSMITTER)
  i2c.write(I2C_ID, {addr, data})
  i2c.stop(I2C_ID)
end

--OK
local function set_rgb(r, g, b)
  set_reg(REG_RED, r)
  set_reg(REG_GREEN, g)
  set_reg(REG_BLUE, b)
end

--OK
local function set_color_white()
  set_rgb(255, 255, 255)
end

--OK
local function display()
  display_control = bor(display_control, LCD_DISPLAYON)
  command(bor(LCD_DISPLAYCONTROL, display_control))
end

--?
local function no_display()
  display_control = band(display_control, bnot(LCD_DISPLAYON))
  command(bor(LCD_DISPLAYCONTROL, display_control))
end

--OK
local function cursor()
  display_control = bor(display_control, LCD_CURSORON)
  command(bor(LCD_DISPLAYCONTROL, display_control))
end

--OK
local function no_cursor()
  display_control = band(display_control, bnot(LCD_CURSORON))
  command(bor(LCD_DISPLAYCONTROL, display_control))
end

--OK
local function clear()
  command(LCD_CLEARDISPLAY)
  tmr.delay(2000)
end

--OK
local function begin(cols, lines, dotsize)
  dotsize = dotsize or LCD_5x8DOTS
  
  i2c.setup(I2C_ID, SDA, SCL, i2c.SLOW)

  display_function = 0
  if (lines > 1) then
    display_function = bor(display_function, LCD_2LINE)
  end

  if (dotsize ~= LCD_5x8DOTS and lines == 1) then
    display_function = bor(display_function, LCD_5x10DOTS)
  end

  -- SEE PAGE 45/46 FOR INITIALIZATION SPECIFICATION!
  -- according to datasheet, we need at least 40ms after power rises above 2.7V
  -- before sending commands. Arduino can turn on way befer 4.5V so we'll wait 50
  tmr.delay(50000)

  -- this is according to the hitachi HD44780 datasheet
  -- page 45 figure 23

  -- Send function set command sequence
  command(bor(LCD_FUNCTIONSET, display_function))
  tmr.delay(4500)

  -- second try
  command(bor(LCD_FUNCTIONSET, display_function))
  tmr.delay(150)

  -- third go
  command(bor(LCD_FUNCTIONSET, display_function))

  -- finally, set # lines, font size, etc.
  command(bor(LCD_FUNCTIONSET, display_function))

  -- turn the display on with no cursor or blinking default
  display_control = bor(LCD_DISPLAYON, LCD_CURSOROFF, LCD_BLINKOFF)
  display()

  -- clear it off
  clear()

  -- Initialize to default text direction (for romance languages)
  display_mode = bor(LCD_ENTRYLEFT, LCD_ENTRYSHIFTDECREMENT)
  -- set the entry mode
  command(bor(LCD_ENTRYMODESET, display_mode))

  -- backlight init
  set_reg(REG_MODE1, 0)
  -- set LEDs controllable by both PWM and GRPPWM registers
  set_reg(REG_OUTPUT, 0xFF)
  -- set MODE2 values
  -- 0010 0000 -> 0x20  (DMBLNK to 1, ie blinky mode)
  set_reg(REG_MODE2, 0x20)
end

--OK
local function lcd_print(str)
  for i = 1, str:len() do
    x = str:sub(i, i)
    if (x == "\n") then
      set_cursor(0, 1)
    else
      write(x:byte(1))
    end
  end
end


function update()
  http.get('http://192.168.1.192:5000/api/v1/weather',
    nil,
    function(code, data)
      if (code < 0) then
        lcd_print("HTTP request failed")
      else
        print(data)
        clear()
        lcd_print(data)
      end
    end)
end




backlight = false

function toggle_backlight()
  backlight = not backlight
  if backlight then
    set_color_white()
    tmr.alarm(BACKLIGHT_TIMER, 3 * SECOND, tmr.ALARM_SINGLE, toggle_backlight)
  else
    tmr.stop(BACKLIGHT_TIMER)
    set_rgb(0, 0, 0)
  end
end

function on_backlight(level)
  toggle_backlight()
end

function main()
  wifi.setmode(wifi.STATION)
  wifi.sta.config("Linksys01669","cddsvkhacs")
  wifi.sta.connect()

  gpio.mode(6, gpio.INT)
  gpio.trig(6, "down", on_backlight)
  
  i2c.setup(I2C_ID, SDA, SCL, i2c.SLOW)

  begin(16, 2)
  toggle_backlight()
  lcd_print("Love Bunny ~\nWeather Station")
  
  tmr.alarm(SPLASH_DELAY, 4 * SECOND, tmr.ALARM_SINGLE,
      function()
        update()
        tmr.alarm(UPDATE_TIMER, 5 * MINUTE, tmr.ALARM_AUTO, update)
      end)
end



SECOND = 1000
MINUTE = 60 * SECOND
PANIC_SAFTY_INTERVAL = 2 * SECOND

INIT_TIMER = 0
SPLASH_DELAY = 1
UPDATE_TIMER = 2
BACKLIGHT_TIMER = 3

tmr.alarm(INIT_TIMER, PANIC_SAFTY_INTERVAL, tmr.ALARM_SINGLE, main)
