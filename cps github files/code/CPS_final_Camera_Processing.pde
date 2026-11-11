import processing.video.*;
import oscP5.*;
import netP5.*;

Capture cam;

int cameraWidth = 1280;
int cameraHeight = 720;

int previewSize = 500;

PImage circularImage;

OscP5 oscP5;
NetAddress wekinator;

int inputPort = 6448;
int outputPort = 12000;

int gridSize = 44;

int totalInputs = gridSize * gridSize; // 1936 GRID INPUT

float[] features = new float[totalInputs];

PImage featureImage;

float prediction = 0;
boolean receivedOutput = false;

int sendCounter = 0;


int cropSize;
int cropX;
int cropY;


void setup() {

  size(900, 650);
  background(0);

  println("Starting external camera via GStreamer Pipeline...");
  
  cam = new Capture(
    this,
    cameraWidth,
    cameraHeight,
    "pipeline:avfvideosrc device-index=0",
    30
  );

  cam.start();

  circularImage = createImage(
    previewSize,
    previewSize,
    ARGB
  );

  featureImage = createImage(
    gridSize,
    gridSize,
    RGB
  );

  oscP5 = new OscP5(this, outputPort);

  wekinator = new NetAddress(
    "127.0.0.1",
    inputPort
  );

  println("--------------------------");
  println("OSC initialized");
  println("Input port: 6448");
  println("Output port: 12000");
  println("Total inputs: " + totalInputs);
  println("--------------------------");
}


void draw() {

  background(15);

  // Read new camera frame
  if (cam.available()) {

    cam.read();

    if (cam.width > 0 && cam.height > 0 && cam.pixels.length > 0) {

      cropSize = min(cam.width, cam.height);

      cropX = (cam.width - cropSize) / 2;
      cropY = (cam.height - cropSize) / 2;

      createCircularImage();

      extractFeatures();

      if (frameCount % 3 == 0) {
        sendToWekinator();
        sendCounter++;
      }
    }
  }

  image(
    circularImage,
    40,
    75,
    previewSize,
    previewSize
  );

  image(
    featureImage,
    620,
    110,
    220,
    220
  );

  fill(255);
  textSize(20);

  text("CIRCULAR CAMERA INPUT", 40, 40);
  text("FEATURE MAP", 620, 75);

  textSize(14);
  fill(0, 255, 100);

  text("CAMERA: LIVE", 40, 610);

  fill(255);

  text(
    "Resolution: " + cam.width + " x " + cam.height,
    40,
    635
  );

  text(
    "Wekinator Inputs: " + totalInputs,
    620,
    380
  );

  text(
    "Sent frames: " + sendCounter,
    620,
    405
  );

  text(
    "OSC Send: 127.0.0.1:6448",
    620,
    445
  );

  text(
    "OSC Receive: 12000",
    620,
    470
  );

  textSize(20);

  if (receivedOutput) {
    fill(0, 255, 100);
    text(
      "CLASS: " + round(prediction),
      620,
      530
    );
  } else {
    fill(255, 180, 0);
    text(
      "WAITING FOR WEKINATOR",
      620,
      530
    );
  }
}

void createCircularImage() {

  cam.loadPixels();
  circularImage.loadPixels();

  for (int y = 0; y < previewSize; y++) {
    for (int x = 0; x < previewSize; x++) {

      float nx = (x - previewSize / 2.0) / (previewSize / 2.0);
      float ny = (y - previewSize / 2.0) / (previewSize / 2.0);

      int index = x + y * previewSize;

      if (nx * nx + ny * ny > 1.0) {
        circularImage.pixels[index] = color(0, 0, 0, 0);
      } else {
        int sx = constrain(cropX + int(x * cropSize / (float)previewSize), 0, cam.width - 1);
        int sy = constrain(cropY + int(y * cropSize / (float)previewSize), 0, cam.height - 1);

        int sourceIndex = sx + sy * cam.width;

        color c = cam.pixels[sourceIndex];

        circularImage.pixels[index] = color(red(c), green(c), blue(c), 255);
      }
    }
  }

  circularImage.updatePixels();
}


void extractFeatures() {

  cam.loadPixels();
  featureImage.loadPixels();

  int index = 0;

  for (int y = 0; y < gridSize; y++) {
    for (int x = 0; x < gridSize; x++) {

      float nx = 2.0 * (x + 0.5) / gridSize - 1.0;
      float ny = 2.0 * (y + 0.5) / gridSize - 1.0;

      if (nx * nx + ny * ny > 1.0) {
        features[index] = 0.0;
        featureImage.pixels[index] = color(0);
      } else {
        int sx = constrain(cropX + int((x + 0.5) * cropSize / gridSize), 0, cam.width - 1);
        int sy = constrain(cropY + int((y + 0.5) * cropSize / gridSize), 0, cam.height - 1);

        int loc = sx + sy * cam.width;
        color c = cam.pixels[loc];

        float brightnessValue = 0.299 * red(c) + 0.587 * green(c) + 0.114 * blue(c);

        features[index] = brightnessValue / 255.0; 
        featureImage.pixels[index] = color(brightnessValue);
      }

      index++;
    }
  }

  featureImage.updatePixels();
}

void sendToWekinator() {
  OscMessage msg = new OscMessage("/wek/inputs");

  for (int i = 0; i < totalInputs; i++) {
    msg.add(features[i]);
  }

  oscP5.send(msg, wekinator);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/wek/outputs")) {
    if (msg.arguments().length > 0) {
      prediction = msg.get(0).floatValue();
      receivedOutput = true;
    }
  }
}
