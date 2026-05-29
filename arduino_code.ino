#include <Wire.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

#define MPU_ADDR 0x68
#define MOTOR 25

BLECharacteristic *pCharacteristic;

#define SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_UUID "abcd1234-5678-1234-5678-123456789abc"

float baseline;

// 🔥 MODE VARIABLE
int mode = 1; // 0 = strict, 1 = moderate, 2 = lenient

//////////////////////////////////////////////////////
// 📩 RECEIVE MODE FROM FLUTTER
//////////////////////////////////////////////////////

class MyCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    std::string value = pChar->getValue();

    if (value.length() > 0) {

      Serial.print("Received: ");
      Serial.println(value.c_str());

      if (value == "0") mode = 0;
      else if (value == "1") mode = 1;
      else if (value == "2") mode = 2;

      Serial.print("Mode updated: ");
      Serial.println(mode);
    }
  }
};

//////////////////////////////////////////////////////

void setup() {

  Serial.begin(115200);
  Wire.begin();

  pinMode(MOTOR, OUTPUT);

  // Wake MPU6050
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0);
  Wire.endTransmission(true);

  Serial.println("Calibrating...");
  delay(3000);

  baseline = getAngle();

  //////////////////////////////////////////////////////
  // 🔵 BLE SETUP
  //////////////////////////////////////////////////////

  BLEDevice::init("PostureDevice");

  BLEServer *pServer = BLEDevice::createServer();

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_NOTIFY |
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_WRITE   // 🔥 IMPORTANT
                    );

  pCharacteristic->addDescriptor(new BLE2902());

  // 🔥 attach callback
  pCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();

  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);

  BLEDevice::startAdvertising();

  Serial.println("BLE started");
}

//////////////////////////////////////////////////////

void loop() {

  float angle = getAngle();
  float deviation = abs(angle - baseline);

  String posture;

  //////////////////////////////////////////////////////
  // 🎯 MODE-BASED THRESHOLD
  //////////////////////////////////////////////////////

  float threshold;

  if (mode == 0) threshold = 5;       // STRICT
  else if (mode == 1) threshold = 10; // MODERATE
  else threshold = 15;                // LENIENT

  //////////////////////////////////////////////////////

  if (deviation < threshold)
      posture = "GOOD";
  else
      posture = "SLOUCH";

  //////////////////////////////////////////////////////
  // 🔔 MOTOR CONTROL
  //////////////////////////////////////////////////////

  if (posture == "SLOUCH")
      digitalWrite(MOTOR, HIGH);
  else
      digitalWrite(MOTOR, LOW);

  //////////////////////////////////////////////////////
  // 📡 SEND DATA TO APP
  //////////////////////////////////////////////////////

  String packet = posture + "," + String(angle,1) + "," + String(threshold,1);

  pCharacteristic->setValue(packet.c_str());
  pCharacteristic->notify();

  //////////////////////////////////////////////////////

  Serial.print("Mode: ");
  Serial.print(mode);
  Serial.print(" | Threshold: ");
  Serial.print(threshold);
  Serial.print(" | Angle: ");
  Serial.print(angle);
  Serial.print(" | Posture: ");
  Serial.println(posture);

  delay(2000);
}

//////////////////////////////////////////////////////

float getAngle() {

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR,6,true);

  int16_t ax = Wire.read()<<8 | Wire.read();
  int16_t ay = Wire.read()<<8 | Wire.read();
  int16_t az = Wire.read()<<8 | Wire.read();

  float accelX = ax/16384.0;
  float accelZ = az/16384.0;

  return atan2(accelX, accelZ) * 180 / PI;
}