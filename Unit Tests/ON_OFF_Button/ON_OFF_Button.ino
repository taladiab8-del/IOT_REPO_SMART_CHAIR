
const int switchPin =18;  // ON/OFF toggle switch pin
int switchState = 0;

void setup() {
  Serial.begin(9600);
  pinMode(switchPin, INPUT_PULLDOWN); 
}

void loop() {
  switchState = digitalRead(switchPin);

  if (switchState == HIGH) {
    Serial.println("Switch is ON");
  } else {
    Serial.println("Switch is OFF");
  }

  delay(300);
}

