/*
 * Wekinator (OSC) -> Processing -> Arduino
 *
 * Required library: oscP5
 *   (Sketch -> Import Library -> Manage Libraries, search "oscP5")
 *
 * Wekinator settings:
 *   Output type: Classifier (classes 1..NUM_CLASSES)
 *   Send outputs to localhost:12000, message /wek/outputs (Wekinator defaults)
 *
 * Message sent to Arduino:  C3\n   (plain text, one per line)
 * Arduino replies:          ACK 3
 *
 * Safety features:
 *   1. Accepts float or int from Wekinator and rounds to a class number
 *   2. A class must stay the same for STABLE_MS before it is sent (no flicker)
 *   3. Sends only on change + resends once per second (never floods the Arduino)
 *   4. Text + newline protocol, so no byte-vs-character mismatch
 *   5. Window shows: received / stable / sent / confirmed by Arduino
 */

import oscP5.*;
import netP5.*;
import processing.serial.*;

// ======== Settings ========
final int    OSC_PORT    = 12000;
final String OSC_ADDR    = "/wek/outputs";
final String PORT_HINT   = "usbmodem";  // part of the Arduino port name on Mac; on Windows use e.g. "COM3"
final int    BAUD        = 115200;
final int    NUM_CLASSES = 5;           // must match the number of classes in Wekinator
final int    STABLE_MS   = 200;         // how long a class must hold before sending
final int    RESEND_MS   = 1000;        // periodic resend, in case the Arduino resets
// ==========================

OscP5 osc;
Serial port;
String portName = "";
long lastOpenTry = 0;

// Written by the OSC thread, read by draw()
volatile int  rawClass  = 0;
volatile long lastOscMs = 0;
volatile int  oscCount  = 0;
volatile String lastOscInfo = "";
volatile int  anyOscCount = 0;          // all OSC messages on this port, any address
volatile String lastOtherAddr = "";     // last address that was NOT OSC_ADDR

int  candidate = 0;
long candidateSince = 0;
int  stableClass = 0;
int  sentClass = 0;
long lastSendMs = 0;
int  ackClass = 0;
long lastAckMs = 0;
String serialBuf = "";
ArrayList<String> logLines = new ArrayList<String>();

void setup() {
  size(680, 460);
  surface.setTitle("Wekinator -> Arduino");
  osc = new OscP5(this, OSC_PORT);
  println("Serial ports:");
  printArray(Serial.list());
  openSerial();
}

void openSerial() {
  lastOpenTry = millis();
  try {
    for (String p : Serial.list()) {
      if (p.contains(PORT_HINT) && !p.contains("/dev/tty.")) {   // on Mac use /dev/cu.*, not /dev/tty.*
        port = new Serial(this, p, BAUD);
        port.clear();
        portName = p;
        sentClass = 0;   // resend the current class right after connecting
        addLog("Serial opened: " + p);
        return;
      }
    }
    addLog("No port matching \"" + PORT_HINT + "\"");
  } catch (Exception e) {
    port = null;
    addLog("Serial open failed: " + e.getMessage() + "  (Arduino IDE / web page still using it?)");
  }
}

// ---------- Receive from Wekinator ----------
void oscEvent(OscMessage m) {
  anyOscCount++;
  if (!m.checkAddrPattern(OSC_ADDR)) {
    // Something arrived on this port, but with a different name: show it
    lastOtherAddr = m.addrPattern();
    return;
  }
  Object[] args = m.arguments();
  if (args.length == 0) return;

  float v;
  Object a = args[0];
  if (a instanceof Float)        v = (Float) a;
  else if (a instanceof Integer) v = (Integer) a;
  else if (a instanceof Double)  v = ((Double) a).floatValue();
  else return;

  int c = round(v);
  lastOscInfo = m.typetag() + " " + v;
  lastOscMs = millis();
  oscCount++;
  if (c >= 1 && c <= NUM_CLASSES) rawClass = c;
}

// ---------- Main loop ----------
void draw() {
  long now = millis();

  // If the serial port is closed, retry every 2 seconds
  if (port == null && now - lastOpenTry > 2000) openSerial();

  // 1. Stability check
  int r = rawClass;
  if (r != candidate) { candidate = r; candidateSince = now; }
  if (candidate != 0 && candidate != stableClass && now - candidateSince >= STABLE_MS) {
    stableClass = candidate;
    addLog("Class -> " + stableClass);
  }

  // 2. Send immediately on change, otherwise resend once per RESEND_MS
  if (port != null && stableClass != 0 &&
      (stableClass != sentClass || now - lastSendMs >= RESEND_MS)) {
    sendClass(stableClass);
  }

  // 3. Read replies from the Arduino
  readSerial();

  drawUI(now);
}

void sendClass(int c) {
  try {
    port.write("C" + c + "\n");
    if (c != sentClass) addLog("Sent C" + c);
    sentClass = c;
    lastSendMs = millis();
  } catch (Exception e) {
    addLog("Write failed, reconnecting: " + e.getMessage());
    closePort();
  }
}

void readSerial() {
  if (port == null) return;
  try {
    while (port.available() > 0) {
      char ch = port.readChar();
      if (ch == '\n' || ch == '\r') {
        if (serialBuf.length() > 0) handleLine(serialBuf.trim());
        serialBuf = "";
      } else if (serialBuf.length() < 80) {
        serialBuf += ch;
      }
    }
  } catch (Exception e) {
    addLog("Read failed: " + e.getMessage());
    closePort();
  }
}

void handleLine(String line) {
  if (line.startsWith("ACK ")) {
    ackClass = int(line.substring(4).trim());
    lastAckMs = millis();
  } else {
    addLog("Arduino: " + line);
    if (line.startsWith("READY")) sentClass = 0;   // Arduino restarted, resend now
  }
}

void closePort() {
  try { if (port != null) port.stop(); } catch (Exception e) {}
  port = null;
}

void addLog(String s) {
  String t = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2) + "  " + s;
  println(t);
  logLines.add(t);
  while (logLines.size() > 9) logLines.remove(0);
}

// ---------- UI ----------
void drawUI(long now) {
  background(18);
  boolean oscAlive = now - lastOscMs < 1000;
  boolean ackOk = port != null && sentClass != 0 && ackClass == sentClass && now - lastAckMs < 2500;

  box(20,  "Wekinator", rawClass, oscAlive ? color(79, 209, 165) : color(229, 83, 75),
      oscAlive ? "receiving" : "no OSC on " + OSC_PORT);
  box(185, "Stable",    stableClass, color(230), "after " + STABLE_MS + " ms");
  box(350, "Sent",      sentClass,   port != null ? color(230) : color(229, 83, 75),
      port != null ? "serial OK" : "serial closed");
  box(515, "Arduino",   ackClass,    ackOk ? color(79, 209, 165) : color(240, 160, 75),
      ackOk ? "confirmed" : "waiting ACK");

  fill(140);
  textSize(13);
  text("Port: " + (port != null ? portName : "-") + "    OSC msgs: " + oscCount + " / any: " + anyOscCount + "    last: " + lastOscInfo, 20, 200);
  if (lastOtherAddr.length() > 0) {
    fill(240, 160, 75);
    text("Other OSC address received: " + lastOtherAddr + "   (expected " + OSC_ADDR + ")", 20, 220);
  }

  fill(120);
  for (int i = 0; i < logLines.size(); i++) text(logLines.get(i), 20, 250 + i * 22);
}

void box(int x, String title, int value, int c, String sub) {
  noFill();
  stroke(60);
  rect(x, 20, 145, 150, 10);
  noStroke();
  fill(150);
  textSize(14);
  text(title, x + 12, 44);
  fill(c);
  textSize(64);
  text(value == 0 ? "-" : str(value), x + 12, 120);
  fill(c);
  textSize(12);
  text(sub, x + 12, 155);
}
