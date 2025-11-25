// chair_training.ino
// Training RAW streaming for Excel that has columns:
// s1..s11, label, b1..b5, p1, dp1, p2, dp2, p3, dp3, p4, dp4, p5, dp5, r
//
// Flow:
// 1) First OFF->ON captures BASELINE (sit normal): prints BASELINE_SAVED + BASE_RAW_CSV
// 2) Every next OFF->ON prints SAMPLE_RAW_CSV + END_SAMPLE
//
// Python script will ask label and will compute p/dp/r and fill b1..b5.

#include <Wire.h>
#include <math.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

// --------- Pins ----------
const int sensor1Pin = 35;
const int sensor2Pin = 39;
const int sensor3Pin = 33;
const int sensor4Pin = 34;
const int sensor5Pin = 32;

const int switchPin  = 18;   // ON/OFF switch

Adafruit_MPU6050 mpu;

// switch edge detect
int lastSwitchState = LOW;

// --------- Sampling window ----------
const int N_SAMPLES_AVG   = 50; 
const int SAMPLE_DELAY_MS = 80;  

// --------- Baseline state (FSR only) ----------
bool baselineSet = false;
float baseFSR[5] = {0,0,0,0,0};

// ---------- Read MPU ----------
static inline void readMPU(float &ax, float &ay, float &az,
                           float &gx, float &gy, float &gz) {
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  ax = a.acceleration.x;
  ay = a.acceleration.y;
  az = a.acceleration.z;

  gx = g.gyro.x;
  gy = g.gyro.y;
  gz = g.gyro.z;
}

void sampleAverages(float &s1, float &s2, float &s3, float &s4, float &s5,
                    float &ax, float &ay, float &az,
                    float &gx, float &gy, float &gz) {
  long s1_sum=0, s2_sum=0, s3_sum=0, s4_sum=0, s5_sum=0;
  float ax_sum=0, ay_sum=0, az_sum=0, gx_sum=0, gy_sum=0, gz_sum=0;

  for (int i = 0; i < N_SAMPLES_AVG; i++) {
    s1_sum += analogRead(sensor1Pin);
    s2_sum += analogRead(sensor2Pin);
    s3_sum += analogRead(sensor3Pin);
    s4_sum += analogRead(sensor4Pin);
    s5_sum += analogRead(sensor5Pin);

    float _ax,_ay,_az,_gx,_gy,_gz;
    readMPU(_ax,_ay,_az,_gx,_gy,_gz);
    ax_sum += _ax; ay_sum += _ay; az_sum += _az;
    gx_sum += _gx; gy_sum += _gy; gz_sum += _gz;

    delay(SAMPLE_DELAY_MS);
  }

  s1 = s1_sum / (float)N_SAMPLES_AVG;
  s2 = s2_sum / (float)N_SAMPLES_AVG;
  s3 = s3_sum / (float)N_SAMPLES_AVG;
  s4 = s4_sum / (float)N_SAMPLES_AVG;
  s5 = s5_sum / (float)N_SAMPLES_AVG;

  ax = ax_sum / (float)N_SAMPLES_AVG;
  ay = ay_sum / (float)N_SAMPLES_AVG;
  az = az_sum / (float)N_SAMPLES_AVG;

  gx = gx_sum / (float)N_SAMPLES_AVG;
  gy = gy_sum / (float)N_SAMPLES_AVG;
  gz = gz_sum / (float)N_SAMPLES_AVG;
}

void handleOffToOn() {
  Serial.println("Sampling...");

  float s1,s2,s3,s4,s5, ax,ay,az, gx,gy,gz;
  sampleAverages(s1,s2,s3,s4,s5, ax,ay,az, gx,gy,gz);

  if (!baselineSet) {
    baseFSR[0]=s1; baseFSR[1]=s2; baseFSR[2]=s3; baseFSR[3]=s4; baseFSR[4]=s5;
    baselineSet = true;

    Serial.println("BASELINE_SAVED");
    Serial.print("BASE_RAW_CSV=");
    Serial.print(baseFSR[0], 4); Serial.print(",");
    Serial.print(baseFSR[1], 4); Serial.print(",");
    Serial.print(baseFSR[2], 4); Serial.print(",");
    Serial.print(baseFSR[3], 4); Serial.print(",");
    Serial.println(baseFSR[4], 4);

    return;
  }

  Serial.print("SAMPLE_RAW_CSV=");
  Serial.print(s1, 4); Serial.print(",");
  Serial.print(s2, 4); Serial.print(",");
  Serial.print(s3, 4); Serial.print(",");
  Serial.print(s4, 4); Serial.print(",");
  Serial.print(s5, 4); Serial.print(",");
  Serial.print(ax, 4); Serial.print(",");
  Serial.print(ay, 4); Serial.print(",");
  Serial.print(az, 4); Serial.print(",");
  Serial.print(gx, 4); Serial.print(",");
  Serial.print(gy, 4); Serial.print(",");
  Serial.println(gz, 4);

  Serial.println("END_SAMPLE");
}

void setup() {
  Serial.begin(115200);
  delay(1500);

  pinMode(switchPin, INPUT_PULLDOWN);

  pinMode(sensor1Pin, INPUT);
  pinMode(sensor2Pin, INPUT);
  pinMode(sensor3Pin, INPUT);
  pinMode(sensor4Pin, INPUT);
  pinMode(sensor5Pin, INPUT);

  Wire.begin();
  if (!mpu.begin()) {
    Serial.println("Failed to find MPU6050 chip");
    while (1) delay(10);
  }
  mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  lastSwitchState = digitalRead(switchPin);

  Serial.println("TRAINING RAW MODE:");
  Serial.println("1) OFF->ON (first time): sit NORMAL -> capture baseline (FSR) only");
  Serial.println("2) OFF->ON (next times): outputs SAMPLE_RAW_CSV + END_SAMPLE (Python logs row)");
  Serial.print("N_SAMPLES_AVG="); Serial.print(N_SAMPLES_AVG);
  Serial.print(" SAMPLE_DELAY_MS="); Serial.println(SAMPLE_DELAY_MS);
}

void loop() {
  int currentState = digitalRead(switchPin);

  if (currentState != lastSwitchState) {
    delay(30);
    int confirmState = digitalRead(switchPin);

    if (confirmState == HIGH && lastSwitchState == LOW) {
      handleOffToOn();
    }

    lastSwitchState = confirmState;
  }

  delay(10);
}
