#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

Adafruit_MPU6050 mpu;

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("Booting...");

  // ESP32 I2C pins
  Wire.begin(21, 22);   // SDA = 21, SCL = 22
  Serial.println("I2C started on SDA=21, SCL=22");

  Serial.println("Initializing Adafruit MPU6050...");

  if (!mpu.begin(0x68, &Wire)) {
    Serial.println("Failed to find MPU6050 chip at 0x68!");
    Serial.println("Check wiring or try address 0x69.");
    // Do NOT block here – let loop() keep running
  } else {
    Serial.println("MPU6050 connected!");

    mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

    Serial.println("MPU6050 configured.");
  }

  delay(1000);
}

void loop() {
  sensors_event_t a, g, temp;

  Serial.println("Reading sensor...");
  if (!mpu.getEvent(&a, &g, &temp)) {
    Serial.println("getEvent failed (maybe not connected yet?)");
  } else {
    Serial.print("Accel X: ");
    Serial.print(a.acceleration.x);
    Serial.print("  Y: ");
    Serial.print(a.acceleration.y);
    Serial.print("  Z: ");
    Serial.println(a.acceleration.z);

    Serial.print("Gyro  X: ");
    Serial.print(g.gyro.x);
    Serial.print("  Y: ");
    Serial.print(g.gyro.y);
    Serial.print("  Z: ");
    Serial.println(g.gyro.z);
  }

  Serial.println("-------------------------");
  delay(500);
}