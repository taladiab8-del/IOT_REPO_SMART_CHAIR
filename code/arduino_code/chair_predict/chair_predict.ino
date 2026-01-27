// chair_predict.ino
// Live mode:
// - Switch ON  => continuous sampling/prediction
// - Send to app (Firebase) every 10s OR immediately when posture changes
// - Switch OFF => stop sending + RESET BASELINE 
//
// Motion gate (gyro deviation from baseline bias) => label 6
// Else KNN on normalized FSR features => labels 1..5
// KNN Features must match dataset.h order: [dp1..dp5, p1..p5, r]

#include <Wire.h>
#include <math.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

#include "dataset.h"   // N_SAMPLES, N_FEATURES(=11), FEATURE_MEAN, FEATURE_STD, TRAIN_SAMPLES, TRAIN_LABELS

#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <time.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// ---------- WiFi ----------
#define WIFI_SSID ""
#define WIFI_PASSWORD ""

// ---------- Firebase ----------
#define API_KEY ""
#define DATABASE_URL ""
#define USER_EMAIL ""
#define USER_PASSWORD ""

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

String activeUserId = "chairUser1";
const char* chairId = "chair1";
unsigned long lastUserPollMs = 0;

// --------- Pins ----------
const int sensor1Pin = 35;
const int sensor2Pin = 39;
const int sensor3Pin = 33;
const int sensor4Pin = 34;
const int sensor5Pin = 32;

const int switchPin  = 18;

// --------- MPU ----------
Adafruit_MPU6050 mpu;

// --------- Sampling window ----------
const int N_SAMPLES_AVG   = 60;  
const int SAMPLE_DELAY_MS = 25;  

// --------- Sending policy ----------
const unsigned long LIVE_PERIOD_MS     = 10000; // periodic send every 10s
const unsigned long MIN_CHANGE_GAP_MS  = 1500;  

int lastSentPrediction = -1;
unsigned long lastSendMs = 0;

// --------- History throttling ----------
unsigned long lastHistoryPushMs = 0;
const unsigned long HISTORY_MIN_INTERVAL_MS = 60000; 
int lastHistoryPrediction = -1;

// --------- Motion thresholds (gyro deviation from baseline bias, rad/s) ----------
const float GYRO_DEV_TH_AVG = 0.30f;
const float GYRO_DEV_TH_MAX = 0.80f;

// --------- Baseline for FSR normalized features ----------
bool baselineSet = false;
float pb[5] = {0, 0, 0, 0, 0};   // baseline distribution p_i
float Bsum  = 0.0f;              // baseline total load
const float EPS_F = 1.0f;      

// --------- Gyro bias captured at baseline ----------
bool gyroBiasSet = false;
float gx0 = 0.0f, gy0 = 0.0f, gz0 = 0.0f;

// --------- For switch OFF detection ----------
bool prevSwitchOn = false;

// ===================== Utility =====================
void resetBaseline() {
  baselineSet = false;
  Bsum = 0.0f;
  for (int i = 0; i < 5; i++) pb[i] = 0.0f;

  gyroBiasSet = false;
  gx0 = gy0 = gz0 = 0.0f;

  lastSentPrediction = -1;
  lastSendMs = 0;
}

void readMPU(float &ax, float &ay, float &az,
             float &gx, float &gy, float &gz) {
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  ax = a.acceleration.x;
  ay = a.acceleration.y;
  az = a.acceleration.z;

  gx = g.gyro.x; // rad/s
  gy = g.gyro.y;
  gz = g.gyro.z;
}

// ===================== WiFi/Firebase =====================
void connectWiFi() {
  Serial.println("== WIFI ==");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("Connecting to WiFi");
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    Serial.print(".");
    delay(400);
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("WiFi connected. IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi FAILED.");
  }
}

void initTime() {
  Serial.println("== TIME ==");
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  Serial.print("Syncing time");
  unsigned long start = millis();
  time_t now = time(nullptr);

  while (now < 1700000000 && millis() - start < 15000) {
    Serial.print(".");
    delay(300);
    now = time(nullptr);
  }
  Serial.println();

  if (now >= 1700000000) Serial.println("Time OK.");
  else Serial.println("Time sync FAILED. Continuing...");
}

void initFirebase() {
  Serial.println("== FIREBASE ==");
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;

  Firebase.reconnectWiFi(true);
  fbdo.setResponseSize(2048);

  Firebase.begin(&config, &auth);

  Serial.print("Waiting for Firebase");
  unsigned long start = millis();
  while (!Firebase.ready() && millis() - start < 20000) {
    Serial.print(".");
    delay(300);
  }
  Serial.println();

  if (Firebase.ready()) Serial.println("Firebase ready");
  else Serial.println("Firebase NOT ready");
}

bool sendPredictionToFirebase(int prediction) {
  if (!Firebase.ready()) return false;

  FirebaseJson json;
  json.set("prediction", prediction);
  json.set("ts", (int)time(nullptr));
  json.set("device", "esp32");

  String path = "/users/" + activeUserId + "/live/posture";
  bool ok = Firebase.RTDB.setJSON(&fbdo, path.c_str(), &json);
  if (!ok) {
    Serial.print("RTDB live write failed: ");
    Serial.println(fbdo.errorReason());
  }
  return ok;
}

bool pushHistoryIfAllowed(int prediction) {
  if (!Firebase.ready()) return false;

  unsigned long nowMs = millis();
  bool enoughTime = (nowMs - lastHistoryPushMs) >= HISTORY_MIN_INTERVAL_MS;
  bool changed    = (prediction != lastHistoryPrediction);

  if (!enoughTime && !changed) return true;

  time_t now = time(nullptr);
  struct tm *t = gmtime(&now);

  char dateKey[11];
  snprintf(dateKey, sizeof(dateKey), "%04d-%02d-%02d",
           t->tm_year + 1900, t->tm_mon + 1, t->tm_mday);

  FirebaseJson json;
  json.set("prediction", prediction);
  json.set("ts", (int)now);
  json.set("device", "esp32");

  String path = "/users/" + activeUserId + "/history/" + String(dateKey);

  bool ok = Firebase.RTDB.pushJSON(&fbdo, path.c_str(), &json);
  if (!ok) {
    Serial.print("RTDB history push failed: ");
    Serial.println(fbdo.errorReason());
    return false;
  }

  lastHistoryPushMs = nowMs;
  lastHistoryPrediction = prediction;
  return true;
}

void updateActiveUserFromFirebase() {
  if (!Firebase.ready()) return;

  if (millis() - lastUserPollMs < 3000) return;
  lastUserPollMs = millis();

  String path = String("/chairs/") + chairId + "/activeUserId";
  if (Firebase.RTDB.getString(&fbdo, path.c_str())) {
    String newUser = fbdo.stringData();
    newUser.trim();

    if (newUser.length() > 0 && newUser != activeUserId) {
      activeUserId = newUser;

      // reset baseline for new user
      resetBaseline();

      Serial.print("Active user updated: ");
      Serial.println(activeUserId);
      Serial.println("Baseline reset. Keep switch ON while sitting NORMAL to capture baseline.");
    }
  }
}

// ===================== KNN =====================
void scaleFeatures(const float input[N_FEATURES], float output[N_FEATURES]) {
  for (int j = 0; j < N_FEATURES; ++j) {
    float stdv = FEATURE_STD[j];
    if (stdv == 0.0f) stdv = 1.0f;
    output[j] = (input[j] - FEATURE_MEAN[j]) / stdv;
  }
}

int predictKNN(const float rawFeatures[N_FEATURES]) {
  float features[N_FEATURES];
  scaleFeatures(rawFeatures, features);

  const int K = 7;

  float bestDist[K];
  int bestLabel[K];
  for (int i = 0; i < K; ++i) {
    bestDist[i] = 1e30f;
    bestLabel[i] = -1;
  }

  for (int i = 0; i < N_SAMPLES; ++i) {
    float d = 0.0f;
    for (int j = 0; j < N_FEATURES; ++j) {
      float diff = features[j] - TRAIN_SAMPLES[i][j];
      d += diff * diff;
    }

    int worstIndex = 0;
    float worstDist = bestDist[0];
    for (int t = 1; t < K; ++t) {
      if (bestDist[t] > worstDist) {
        worstDist = bestDist[t];
        worstIndex = t;
      }
    }

    if (d < worstDist) {
      bestDist[worstIndex] = d;
      bestLabel[worstIndex] = TRAIN_LABELS[i];
    }
  }

  int counts[16];
  for (int i = 0; i < 16; ++i) counts[i] = 0;

  for (int i = 0; i < K; ++i) {
    int lbl = bestLabel[i];
    if (lbl >= 0 && lbl < 16) counts[lbl]++;
  }

  int bestLbl = -1;
  int bestCount = -1;
  for (int lbl = 0; lbl < 16; ++lbl) {
    if (counts[lbl] > bestCount) {
      bestCount = counts[lbl];
      bestLbl = lbl;
    }
  }
  return bestLbl;
}

// ===================== Sample -> predict once =====================
bool sampleAndPredictOnce(int &outPrediction) {
  long s1_sum = 0, s2_sum = 0, s3_sum = 0, s4_sum = 0, s5_sum = 0;

  float gx_sum = 0.0f, gy_sum = 0.0f, gz_sum = 0.0f;

  float gyroDev_sum = 0.0f;
  float gyroDev_max = 0.0f;

  for (int i = 0; i < N_SAMPLES_AVG; i++) {
    int v1 = analogRead(sensor1Pin);
    int v2 = analogRead(sensor2Pin);
    int v3 = analogRead(sensor3Pin);
    int v4 = analogRead(sensor4Pin);
    int v5 = analogRead(sensor5Pin);

    s1_sum += v1; s2_sum += v2; s3_sum += v3; s4_sum += v4; s5_sum += v5;

    float ax, ay, az, gx, gy, gz;
    readMPU(ax, ay, az, gx, gy, gz);

    gx_sum += gx; gy_sum += gy; gz_sum += gz;

    if (gyroBiasSet) {
      float dx = gx - gx0;
      float dy = gy - gy0;
      float dz = gz - gz0;
      float dev = sqrtf(dx*dx + dy*dy + dz*dz);
      gyroDev_sum += dev;
      if (dev > gyroDev_max) gyroDev_max = dev;
    }

    delay(SAMPLE_DELAY_MS);
  }

  float s1 = s1_sum / (float)N_SAMPLES_AVG;
  float s2 = s2_sum / (float)N_SAMPLES_AVG;
  float s3 = s3_sum / (float)N_SAMPLES_AVG;
  float s4 = s4_sum / (float)N_SAMPLES_AVG;
  float s5 = s5_sum / (float)N_SAMPLES_AVG;

  float gx_avg = gx_sum / (float)N_SAMPLES_AVG;
  float gy_avg = gy_sum / (float)N_SAMPLES_AVG;
  float gz_avg = gz_sum / (float)N_SAMPLES_AVG;

  // ----- baseline capture -----
  if (!baselineSet) {
    float Sbase = s1 + s2 + s3 + s4 + s5;
    Bsum = Sbase;

    pb[0] = s1 / (Sbase + EPS_F);
    pb[1] = s2 / (Sbase + EPS_F);
    pb[2] = s3 / (Sbase + EPS_F);
    pb[3] = s4 / (Sbase + EPS_F);
    pb[4] = s5 / (Sbase + EPS_F);

    gx0 = gx_avg; gy0 = gy_avg; gz0 = gz_avg;
    gyroBiasSet = true;

    baselineSet = true;

    Serial.println("BASELINE_SAVED. Predictions will start now.");
    return false;
  }

  // ----- motion gate -----
  float gyroDev_avg = gyroDev_sum / (float)N_SAMPLES_AVG;

  if (gyroDev_avg > GYRO_DEV_TH_AVG || gyroDev_max > GYRO_DEV_TH_MAX) {
    outPrediction = 6;
    return true;
  }

  // ----- KNN features -----
  float S = s1 + s2 + s3 + s4 + s5;

  float p1 = s1 / (S + EPS_F);
  float p2 = s2 / (S + EPS_F);
  float p3 = s3 / (S + EPS_F);
  float p4 = s4 / (S + EPS_F);
  float p5 = s5 / (S + EPS_F);

  float dp1 = p1 - pb[0];
  float dp2 = p2 - pb[1];
  float dp3 = p3 - pb[2];
  float dp4 = p4 - pb[3];
  float dp5 = p5 - pb[4];

  float r = logf((S + EPS_F) / (Bsum + EPS_F));

  float rawFeatures[N_FEATURES] = {
    dp1, dp2, dp3, dp4, dp5,
    p1,  p2,  p3,  p4,  p5,
    r
  };

  outPrediction = predictKNN(rawFeatures);
  return true;
}

// ===================== Setup/Loop =====================
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

  Serial.println("== MPU6050 ==");
  if (!mpu.begin()) {
    Serial.println("Failed to find MPU6050 chip");
    while (1) delay(10);
  }
  mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  Serial.println("MPU ready");

  connectWiFi();
  if (WiFi.status() == WL_CONNECTED) {
    initTime();
    initFirebase();
  } else {
    Serial.println("WiFi not connected; Firebase disabled.");
  }

  Serial.println("=== LIVE MODE ===");
  Serial.println("Switch ON  => continuous sampling, send every 10s OR on change.");
  Serial.println("Switch OFF => stop + reset baseline.");
  Serial.println("After turning ON, sit NORMAL (no motion) to capture baseline first.");
}

void loop() {
  updateActiveUserFromFirebase();

  bool isOn = (digitalRead(switchPin) == HIGH);

  // Detect ON->OFF: reset baseline
  if (!isOn && prevSwitchOn) {
    Serial.println("Switch OFF -> stopping live + resetting baseline.");
    resetBaseline();
  }
  prevSwitchOn = isOn;

  if (!isOn) {
    delay(50);
    return;
  }

  // Live: sample continuously
  int prediction = -1;
  bool hasPred = sampleAndPredictOnce(prediction);

  if (!hasPred) {
    delay(20);
    return;
  }

  Serial.print("Pred = ");
  Serial.println(prediction);

  // Send policy: every 10s OR immediately when changed 
  unsigned long nowMs = millis();
  bool periodicDue = (nowMs - lastSendMs) >= LIVE_PERIOD_MS;
  bool changedDue  = (prediction != lastSentPrediction) && ((nowMs - lastSendMs) >= MIN_CHANGE_GAP_MS);

  if (periodicDue || changedDue) {
    Serial.print("Sending to Firebase (reason=");
    Serial.print(periodicDue ? "periodic" : "change");
    Serial.println(")");

    if (sendPredictionToFirebase(prediction)) {
      pushHistoryIfAllowed(prediction);
      lastSendMs = nowMs;
      lastSentPrediction = prediction;
    } else {
      Serial.println("Firebase send failed.");
    }
  }

  delay(10);
}
