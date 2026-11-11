/*
  processing_osc_to_arduino (fixed version)

  Listens for Wekinator OSC messages on port 12000 (/wek/outputs)
  and sends the class number (1~5) to the Arduino as a character '1'~'5'.

  Fixes:
   1. Sends a character ("3") instead of a raw byte (3), so the Arduino's
      '1'~'5' check matches.
   2. Reads the Wekinator value as a float (typetag "f") and rounds it,
      instead of calling intValue() on a float.
   3. arduinoMessage starts at 0, so the very first class (even class 1)
      is sent to the Arduino.

  Based on code by Becky Stewart 2022
*/

import oscP5.*;
import netP5.*;
import processing.serial.*;

OscP5 oscP5;
Serial port;

int arduinoMessage = 0;   // FIX: was 1, so class 1 was never sent at start

void setup() {
  size(256, 150);
  println("Available serial ports:");
  printArray(Serial.list());

  // Change this to your Arduino's port from the printed list.
  // Nano clones usually show up as /dev/cu.usbserial-xxxx or /dev/cu.wchusbserial-xxxx
  // The speed (9600) must match Serial.begin() in the Arduino sketch.
  port = new Serial(this, "/dev/cu.usbmodem1101", 9600);
  // port = new Serial(this, Serial.list()[0], 9600);   // or pick by index
  port.bufferUntil('\n');

  // Listen for Wekinator outputs on port 12000
  oscP5 = new OscP5(this, 12000);
}

void draw() {
  background(30);
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(20);
  text(arduinoMessage == 0 ? "waiting..." : "class " + arduinoMessage, width / 2, height / 2);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/wek/outputs")) {
    int value;
    if (msg.checkTypetag("f")) {
      value = round(msg.get(0).floatValue());   // FIX: read as float
    } else if (msg.checkTypetag("i")) {
      value = msg.get(0).intValue();
    } else {
      println("Unexpected typetag: " + msg.typetag());
      return;
    }
    println("Wekinator value: " + value);
    updateArduino(value);
    return;
  }
  println("Other OSC message: " + msg.addrPattern());
}

// Send to the Arduino only when the class changes
void updateArduino(int newMessage) {
  if (newMessage < 1 || newMessage > 5) return;
  if (newMessage != arduinoMessage) {
    arduinoMessage = newMessage;
    println("-> Arduino: " + arduinoMessage);
    port.write(str(arduinoMessage));   // FIX: send the character '1'~'5'
  }
}

// Print whatever the Arduino sends back (phase / animation changes)
void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line != null) print("Arduino: " + line);
}
