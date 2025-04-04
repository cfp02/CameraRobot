#include <Arduino.h>
#include <TMCStepper.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// Pin Definitions for Motor 1 (using UART1)
#define EN_PIN_1     1    // Enable pin (GPIO1)
#define STEP_PIN_1   2    // Step pin (GPIO2)
#define DIR_PIN_1    3    // Direction pin (GPIO3)
#define RX_PIN_1     8    // UART1 RX pin (GPIO8)
#define TX_PIN_1     7    // UART1 TX pin (GPIO7)

// Pin Definitions for Motor 2 (using UART0)
#define EN_PIN_2     4    // Enable pin (GPIO4)
#define STEP_PIN_2   5    // Step pin (GPIO5)
#define DIR_PIN_2    6    // Direction pin (GPIO6)
#define RX_PIN_2     44   // UART0 RX pin (GPIO44)
#define TX_PIN_2     43   // UART0 TX pin (GPIO43)

#define R_SENSE    0.11f // R_sense resistor value in ohms
#define DRIVER_ADDRESS 0b00   // TMC2209 Driver address according to MS1 and MS2

// Motor Configuration
#define STEPS_PER_REV 200      // 1.8 degree steps
#define MICROSTEPS 16     
#define GEAR_RATIO (170.0/18.0) // 18:170 reduction
#define TOTAL_STEPS_PER_REV (STEPS_PER_REV * MICROSTEPS * GEAR_RATIO)
#define MIN_STEP_DELAY 30      // Minimum step delay (microseconds)
#define DEFAULT_ACCELERATION 3000.0  // Default acceleration in degrees/second²
#define CONTROL_INTERVAL 1000   // Speed update interval in microseconds (1ms)

// BLE UUIDs
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SPEED_CHAR_UUID_1   "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define SPEED_CHAR_UUID_2   "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define STATUS_CHAR_UUID   "5b818d26-7c11-4f24-b87f-4f8a8cc974eb"

// Create TMC2209 UART instances
HardwareSerial SerialTMC1(1);  // Use UART1 for motor 1
HardwareSerial SerialTMC2(0);  // Use UART0 for motor 2
TMC2209Stepper driver1 = TMC2209Stepper(&SerialTMC1, R_SENSE, DRIVER_ADDRESS);
TMC2209Stepper driver2 = TMC2209Stepper(&SerialTMC2, R_SENSE, DRIVER_ADDRESS);

// Global variables
BLEServer* pServer = NULL;
BLECharacteristic* pSpeedCharacteristic1 = NULL;
BLECharacteristic* pSpeedCharacteristic2 = NULL;
BLECharacteristic* pStatusCharacteristic = NULL;
bool deviceConnected = false;

// Motor variables
float targetSpeed1 = 0;    // Target speed in degrees per second for motor 1
float targetSpeed2 = 0;    // Target speed in degrees per second for motor 2
float currentSpeed1 = 0;   // Current speed in degrees per second for motor 1
float currentSpeed2 = 0;   // Current speed in degrees per second for motor 2
bool motorEnabled1 = false;
bool motorEnabled2 = false;
unsigned long lastSpeedUpdate1 = 0;
unsigned long lastSpeedUpdate2 = 0;

// Cached step timing variables for Motor 1
unsigned long lastStepTime1 = 0;
int currentStepDelay1 = MIN_STEP_DELAY;
bool stepState1 = false;

// Cached step timing variables for Motor 2
unsigned long lastStepTime2 = 0;
int currentStepDelay2 = MIN_STEP_DELAY;
bool stepState2 = false;

// BLE callbacks
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      pStatusCharacteristic->setValue("Connected");
      pStatusCharacteristic->notify();
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      targetSpeed1 = 0;
      currentSpeed1 = 0;
      targetSpeed2 = 0;
      currentSpeed2 = 0;
      motorEnabled1 = false;
      motorEnabled2 = false;
      digitalWrite(EN_PIN_1, HIGH);  // Disable motor 1
      digitalWrite(EN_PIN_2, HIGH);  // Disable motor 2
      pStatusCharacteristic->setValue("Disconnected");
      pStatusCharacteristic->notify();
      BLEDevice::startAdvertising();
    }
};

class SpeedCallbacks1: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      if (value.length() > 0) {
        float newSpeed = atof(value.c_str());
        targetSpeed1 = newSpeed;
        
        if (newSpeed == 0) {
          motorEnabled1 = false;
          digitalWrite(EN_PIN_1, HIGH);  // Disable motor 1
          pStatusCharacteristic->setValue("Motor 1 stopped");
        } else {
          motorEnabled1 = true;
          digitalWrite(EN_PIN_1, LOW);   // Enable motor 1
          String status = "Motor 1: " + String(newSpeed, 1) + " deg/s";
          pStatusCharacteristic->setValue(status.c_str());
        }
        pStatusCharacteristic->notify();
      }
    }
};

class SpeedCallbacks2: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      if (value.length() > 0) {
        float newSpeed = atof(value.c_str());
        targetSpeed2 = newSpeed;
        
        if (newSpeed == 0) {
          motorEnabled2 = false;
          digitalWrite(EN_PIN_2, HIGH);  // Disable motor 2
          pStatusCharacteristic->setValue("Motor 2 stopped");
        } else {
          motorEnabled2 = true;
          digitalWrite(EN_PIN_2, LOW);   // Enable motor 2
          String status = "Motor 2: " + String(newSpeed, 1) + " deg/s";
          pStatusCharacteristic->setValue(status.c_str());
        }
        pStatusCharacteristic->notify();
      }
    }
};

void updateSpeed1() {
  unsigned long currentTime = micros();
  if (currentTime - lastSpeedUpdate1 >= CONTROL_INTERVAL) {
    float deltaTime = (currentTime - lastSpeedUpdate1) / 1000000.0; // Convert to seconds
    lastSpeedUpdate1 = currentTime;

    // Calculate maximum speed change for this interval
    float maxSpeedChange = DEFAULT_ACCELERATION * deltaTime;
    
    // Adjust current speed towards target speed with immediate response for small changes
    float speedDiff = targetSpeed1 - currentSpeed1;
    if (abs(speedDiff) < maxSpeedChange) {
      // If we're close to target speed, just set it directly
      currentSpeed1 = targetSpeed1;
    } else if (speedDiff > 0) {
      currentSpeed1 += maxSpeedChange;
    } else {
      currentSpeed1 -= maxSpeedChange;
    }
  }
}

void updateSpeed2() {
  unsigned long currentTime = micros();
  if (currentTime - lastSpeedUpdate2 >= CONTROL_INTERVAL) {
    float deltaTime = (currentTime - lastSpeedUpdate2) / 1000000.0; // Convert to seconds
    lastSpeedUpdate2 = currentTime;

    // Calculate maximum speed change for this interval
    float maxSpeedChange = DEFAULT_ACCELERATION * deltaTime;
    
    // Adjust current speed towards target speed with immediate response for small changes
    float speedDiff = targetSpeed2 - currentSpeed2;
    if (abs(speedDiff) < maxSpeedChange) {
      // If we're close to target speed, just set it directly
      currentSpeed2 = targetSpeed2;
    } else if (speedDiff > 0) {
      currentSpeed2 += maxSpeedChange;
    } else {
      currentSpeed2 -= maxSpeedChange;
    }
  }
}

void step1() {
  if (currentSpeed1 == 0 || !motorEnabled1) return;
  
  unsigned long currentTime = micros();
  
  // Only recalculate step timing when speed changes
  static float lastCalculatedSpeed1 = 0;
  if (currentSpeed1 != lastCalculatedSpeed1) {
    float stepsPerSecond = abs(currentSpeed1) * (TOTAL_STEPS_PER_REV / 360.0);
    currentStepDelay1 = max(MIN_STEP_DELAY, (int)(1000000.0 / stepsPerSecond / 2));
    digitalWrite(DIR_PIN_1, currentSpeed1 > 0 ? HIGH : LOW);
    lastCalculatedSpeed1 = currentSpeed1;
  }
  
  // Check if it's time for the next step
  if (currentTime - lastStepTime1 >= currentStepDelay1) {
    stepState1 = !stepState1;
    digitalWrite(STEP_PIN_1, stepState1 ? HIGH : LOW);
    lastStepTime1 = currentTime;
  }
}

void step2() {
  if (currentSpeed2 == 0 || !motorEnabled2) return;
  
  unsigned long currentTime = micros();
  
  // Only recalculate step timing when speed changes
  static float lastCalculatedSpeed2 = 0;
  if (currentSpeed2 != lastCalculatedSpeed2) {
    float stepsPerSecond = abs(currentSpeed2) * (TOTAL_STEPS_PER_REV / 360.0);
    currentStepDelay2 = max(MIN_STEP_DELAY, (int)(1000000.0 / stepsPerSecond / 2));
    digitalWrite(DIR_PIN_2, currentSpeed2 > 0 ? HIGH : LOW);
    lastCalculatedSpeed2 = currentSpeed2;
  }
  
  // Check if it's time for the next step
  if (currentTime - lastStepTime2 >= currentStepDelay2) {
    stepState2 = !stepState2;
    digitalWrite(STEP_PIN_2, stepState2 ? HIGH : LOW);
    lastStepTime2 = currentTime;
  }
}

void setup() {
  // Initialize Serial for debugging
  Serial.begin(115200);
  Serial.println("Camera Robot Starting...");
  
  // Configure pins for Motor 1
  pinMode(EN_PIN_1, OUTPUT);
  pinMode(STEP_PIN_1, OUTPUT);
  pinMode(DIR_PIN_1, OUTPUT);
  
  // Configure pins for Motor 2
  pinMode(EN_PIN_2, OUTPUT);
  pinMode(STEP_PIN_2, OUTPUT);
  pinMode(DIR_PIN_2, OUTPUT);
  
  digitalWrite(EN_PIN_1, HIGH);     // Initially disable motor 1
  digitalWrite(STEP_PIN_1, LOW);
  digitalWrite(DIR_PIN_1, HIGH);
  
  digitalWrite(EN_PIN_2, HIGH);     // Initially disable motor 2
  digitalWrite(STEP_PIN_2, LOW);
  digitalWrite(DIR_PIN_2, HIGH);

  // Initialize TMC2209 UART for Motor 1
  SerialTMC1.begin(115200, SERIAL_8N1, RX_PIN_1, TX_PIN_1);
  
  // Initialize TMC2209 UART for Motor 2
  SerialTMC2.begin(115200, SERIAL_8N1, RX_PIN_2, TX_PIN_2);
  
  // Configure TMC2209 for Motor 1
  driver1.begin();                 // Start TMC2209
  driver1.toff(5);                // Enables driver in software
  driver1.rms_current(800);       // Set motor current to 800mA
  driver1.microsteps(MICROSTEPS); // Set microsteps
  driver1.en_spreadCycle(false);  // Enable StealthChop quiet stepping mode
  driver1.pwm_autoscale(true);    // Needed for StealthChop

  // Configure TMC2209 for Motor 2
  driver2.begin();                 // Start TMC2209
  driver2.toff(5);                // Enables driver in software
  driver2.rms_current(800);       // Set motor current to 800mA
  driver2.microsteps(MICROSTEPS); // Set microsteps
  driver2.en_spreadCycle(false);  // Enable StealthChop quiet stepping mode
  driver2.pwm_autoscale(true);    // Needed for StealthChop

  // Initialize BLE
  BLEDevice::init("CameraRobot");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // Create BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create BLE Characteristics for Motor 1
  pSpeedCharacteristic1 = pService->createCharacteristic(
    SPEED_CHAR_UUID_1,
    BLECharacteristic::PROPERTY_WRITE
  );
  pSpeedCharacteristic1->setCallbacks(new SpeedCallbacks1());

  // Create BLE Characteristics for Motor 2
  pSpeedCharacteristic2 = pService->createCharacteristic(
    SPEED_CHAR_UUID_2,
    BLECharacteristic::PROPERTY_WRITE
  );
  pSpeedCharacteristic2->setCallbacks(new SpeedCallbacks2());

  pStatusCharacteristic = pService->createCharacteristic(
    STATUS_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusCharacteristic->addDescriptor(new BLE2902());

  // Start the service
  pService->start();

  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  pStatusCharacteristic->setValue("Ready");
  lastSpeedUpdate1 = micros();
  lastSpeedUpdate2 = micros();
  
  Serial.println("Setup complete!");
}

void loop() {
  updateSpeed1();
  step1();
  updateSpeed2();
  step2();
}