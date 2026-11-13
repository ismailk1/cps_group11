#include <Servo.h>
#include <Adafruit_NeoPixel.h>

//pins
int LR_pins[4] = { 6, 8, 11, 4 };  // LR servo of tentacles (t01, t02, t03, t04)
int UD_pins[4] = { 5, 7, 12, 3 };  // UD servo of tentacles
//int LR_pins[4] = {6, 8, 11, 4};   // LR servo of tentacles
//int UD_pins[4] = {1, 1, 1, 1};   // UD servo of tentacles

int head_pin = 21;
int led_pin = 2;

//servo settings
int center = 90;
int head_closed = 10;
int head_open = 160;

unsigned long phase_time = 15000;     // length of the animation phase in ms
unsigned long head_time = 25000;      // length of the lid phase: open, stay open (swap the coil), close
unsigned long head_move_time = 3000;  // how long the lid takes to open, and to close
unsigned long rest_time = 5000;       // short wait after the lid has closed
unsigned long update_time = 20;

//led settings
int led_count = 8;
int led_red = 0;
int led_green = 80;
int led_blue = 255;
unsigned long led_step_time = 60;  // ms per LED in the light wave

//servos
Servo x_servo[4];
Servo y_servo[4];
Servo head_servo;
Adafruit_NeoPixel leds(led_count, led_pin, NEO_GRB + NEO_KHZ800);

//state
int phase = 0;         // 0 = head, 1 = rest, 2 = animate
int animation = 1;     // 1 to 5, the one that is played
int latest_class = 1;  // 1 to 5, the newest class from serial
bool picked = false;   // has this round's class been picked yet
unsigned long phase_start = 0;
unsigned long last_update = 0;
bool led_wave_on = false;
unsigned long led_wave_start = 0;

void setup() {
  Serial.begin(115200);  // must match BAUD in osc_to_arduino.pde
  for (int i = 0; i < 4; i++) {
    x_servo[i].attach(LR_pins[i]);
    y_servo[i].attach(UD_pins[i]);
  }
  head_servo.attach(head_pin);
  leds.begin();
  leds.show();
  restAll();
  Serial.println("READY");
}

void loop() {
  readSerial();

  // each phase has its own length
  unsigned long this_phase_time = phase_time;
  if (phase == 0) this_phase_time = head_time;
  if (phase == 1) this_phase_time = rest_time;

  // check time and go to next phase
  if (millis() - phase_start >= this_phase_time) {
    phase_start = millis();
    phase = phase + 1;
    if (phase > 2) phase = 0;
    Serial.print("phase:");
    Serial.print(phase);
    Serial.println();
    restAll();
    startLedWave();
    picked = false;
  }

  // update servos
  if (millis() - last_update >= update_time) {
    last_update = millis();
    unsigned long t = millis() - phase_start;

    if (phase == 0) moveHead(t);

    // pick the class once, right when the lid starts to close
    // (= the class read in the last second before closing, while the coil is still visible)
    if (phase == 0 && !picked && t >= head_time - head_move_time-2000) {
      animation = latest_class;
      picked = true;
      Serial.print("animation:");
      Serial.println(animation);
    }
    if (phase == 1) restAll();
    if (phase == 2) {
      playAnimation(t);
    }
    updateLedWave();
  }
}

//serial
// Protocol from osc_to_arduino.pde: one line per message, e.g. "C3\n"
// Reply "ACK 3" for every valid message so Processing can confirm it arrived.
// A bare digit line ("3\n", e.g. from the Serial Monitor) is also accepted.
char serial_buf[16];
uint8_t serial_len = 0;
bool serial_overflow = false;

void handleSerialLine(char* s) {
  int a = 0;
  if (s[0] == 'C' || s[0] == 'c') a = atoi(s + 1);
  else if (s[0] >= '1' && s[0] <= '5' && s[1] == 0) a = s[0] - '0';
  if (a < 1 || a > 5) return;  // invalid: ignore, never fall back to 1

  if (a != latest_class) {
    latest_class = a;  // only remembered here, played when the lid closes
    Serial.print("class:");
    Serial.println(latest_class);
  }
  Serial.print("ACK ");
  Serial.println(a);
}

void readSerial() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (serial_len > 0 && !serial_overflow) {
        serial_buf[serial_len] = 0;
        handleSerialLine(serial_buf);
      }
      serial_len = 0;
      serial_overflow = false;
    } else if (serial_len < sizeof(serial_buf) - 1) {
      serial_buf[serial_len++] = c;
    } else {
      serial_overflow = true;  // garbage line, drop it
    }
  }
}

void setTentacle(int i, float x, float y) {
  x_servo[i].write(center + x);
  y_servo[i].write(center + y);
}

void restAll() {
  for (int i = 0; i < 4; i++) {
    setTentacle(i, 0, 0);
  }
  head_servo.write(head_closed);
}

// Returns a value from -1 to 1 that repeats every 'period' ms
float wave(unsigned long t, unsigned long period, float shift) {
  return sin(2 * PI * (t % period) / period + shift);
}

//leds
void startLedWave() {
  led_wave_on = true;
  led_wave_start = millis();
}

void updateLedWave() {
  if (!led_wave_on) return;

  int pos = (millis() - led_wave_start) / led_step_time;
  leds.clear();

  if (pos < led_count) {
    leds.setPixelColor(pos, leds.Color(led_red, led_green, led_blue));
  }
  if (pos - 1 >= 0 && pos - 1 < led_count) {
    leds.setPixelColor(pos - 1, leds.Color(led_red / 4, led_green / 4, led_blue / 4));
  }
  if (pos > led_count) {
    led_wave_on = false;
  }

  leds.show();
}

//head
void moveHead(unsigned long t) {
  // Opens slowly, stays open, then closes slowly
  float amount = 1;
  if (t < head_move_time) amount = (1 - cos(PI * t / head_move_time)) / 2;
  if (t > head_time - head_move_time) amount = (1 - cos(PI * ((float)head_time - t) / head_move_time)) / 2;
  head_servo.write(head_closed + (head_open - head_closed) * amount);
}

void playAnimation(unsigned long t) {
  if (animation == 1) animSlow(t);
  if (animation == 2) animFast(t);
  if (animation == 3) animWave(t);
  if (animation == 4) animSwimUp(t);
  if (animation == 5) animSingle(t);
}

// 1: sea wave, up / down only (4 Y servos move)
// The four tentacles rise and fall one after another, like a wave going around.
void animSlow(unsigned long t) {
  for (int i = 0; i < 4; i++) {
    float shift = -i * PI / 2;  // each tentacle a quarter wave later
    setTentacle(i, 0, 30 * wave(t, 2000, shift));
  }
}

// 2: the same sea wave, left / right only (4 X servos move)
void animFast(unsigned long t) {
  for (int i = 0; i < 4; i++) {
    float shift = -i * PI / 2;
    setTentacle(i, 30 * wave(t, 2000, shift), 0);
  }
}

// 3: one diagonal pair twitches (tentacles 0 + 2), after 2 s the other pair (1 + 3)
// (2 tentacles x 2 servos = 4 servos move)
// Uses millis(), not t, so the 2 s keeps counting across phases.
void animWave(unsigned long t) {
  int pair = (millis() / 2000) % 2;     // 0 = tentacles 0 and 2, 1 = tentacles 1 and 3
  float twitch = 25 * wave(t, 250, 0);  // short, quick jerks
  float side = 10 * wave(t, 250, PI / 2);
  for (int i = 0; i < 4; i++) {
    if (i % 2 == pair) setTentacle(i, side, twitch);
    else setTentacle(i, 0, 0);
  }
}

// 4: dance "cross step" (4 servos move)
// Tentacles 0 and 2 sway left / right in mirror, while 1 and 3 nod up / down in mirror,
// half a beat later. Every 2 beats the nodding pair does a bigger nod.
void animSwimUp(unsigned long t) {
  float sway = 30 * wave(t, 800, 0);
  float nod = 25 * wave(t, 800, PI / 2);
  if ((millis() / 1600) % 2 == 1) nod = nod * 1.4;  // bigger nod every other bar
  setTentacle(0, sway, 0);
  setTentacle(2, -sway, 0);
  setTentacle(1, 0, nod);
  setTentacle(3, 0, -nod);
}

// 5: relay (2 servos move)
// Only one tentacle moves at a time: it draws one big fast circle,
// then passes it on to the next tentacle around, like a baton.
// Uses millis(), so the relay keeps going around across phases.
void animSingle(unsigned long t) {
  int active = (millis() / 1000) % 4;       // which tentacle has the "baton"
  unsigned long local = millis() % 1000;    // time inside its turn
  float r = 35 * sin(PI * local / 1000.0);  // circle grows and shrinks, so it starts and ends straight
  for (int i = 0; i < 4; i++) {
    if (i == active) setTentacle(i, r * wave(local, 1000, 0), r * wave(local, 1000, PI / 2));
    else setTentacle(i, 0, 0);
  }
}