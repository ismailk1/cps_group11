// 舵机测试：串口收到 0~7，对应舵机转到 180 度，再回到 0 度
// 0=D11 1=D12 2=D4 3=D3 4=D8 5=D7 6=D6 7=D5

#include <Servo.h>

const int PINS[] = {11, 12, 4, 3, 8, 7, 6, 5};
Servo s;

void setup() {
  Serial.begin(9600);
  pinMode(13, OUTPUT);
  Serial.println("READY");
}

void loop() {
  if (!Serial.available()) return;
  char c = Serial.read();
  if (c < '0' || c > '7') return;

  int pin = PINS[c - '0'];
  digitalWrite(13, HIGH);            // 收到指令，板载灯亮
  Serial.print("D");
  Serial.println(pin);

  s.attach(pin, 500, 2400);          // 只接通这一个舵机
  s.write(180);
  delay(1000);
  s.write(0);
  delay(1000);
  s.detach();                        // 测完断开，省电

  digitalWrite(13, LOW);
  Serial.println("OK");
}
