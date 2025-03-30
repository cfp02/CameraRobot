#include <Arduino.h>
#include <TMCStepper.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// Pin Definitions
#define EN_PIN     4    // Enable pin
#define STEP_PIN   1    // Step pin
#define DIR_PIN    2    // Direction pin
#define RX_PIN     44   // UART RX pin
#define TX_PIN     43   // UART TX pin
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
#define BLE_MIN_INTERVAL 50    // Minimum time between BLE messages (milliseconds)
#define SPEED_THRESHOLD 0.5    // Minimum speed change to trigger a new message (degrees/second)

// BLE UUIDs
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SPEED_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define ACCEL_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define STATUS_CHAR_UUID   "5b818d26-7c11-4f24-b87f-4f8a8cc974eb"

// Create TMC2209 UART instance
HardwareSerial SerialTMC(1);  // Use hardware serial port 1
TMC2209Stepper driver = TMC2209Stepper(&SerialTMC, R_SENSE, DRIVER_ADDRESS);  // Create TMC driver

// Global variables
BLEServer* pServer = NULL;
BLECharacteristic* pSpeedCharacteristic = NULL;
BLECharacteristic* pAccelCharacteristic = NULL;
BLECharacteristic* pStatusCharacteristic = NULL;
bool deviceConnected = false;
float targetSpeed = 0;    // Target speed in degrees per second
float currentSpeed = 0;   // Current speed in degrees per second
float maxAcceleration = DEFAULT_ACCELERATION;  // Maximum acceleration in degrees/second²
bool motorEnabled = false;
unsigned long lastSpeedUpdate = 0;
unsigned long lastBleUpdate = 0;
float lastReportedSpeed = 0;
float lastReportedAccel = 0;

// BLE callbacks
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      pStatusCharacteristic->setValue("Connected");
      pStatusCharacteristic->notify();
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      targetSpeed = 0;
      currentSpeed = 0;
      motorEnabled = false;
      maxAcceleration = DEFAULT_ACCELERATION;
      digitalWrite(EN_PIN, HIGH);  // Disable motor
      pStatusCharacteristic->setValue("Disconnected");
      pStatusCharacteristic->notify();
      BLEDevice::startAdvertising();
    }
};

class SpeedCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      if (value.length() > 0) {
        float newSpeed = atof(value.c_str());
        targetSpeed = newSpeed;
        
        // Always update status immediately with target speed
        if (newSpeed == 0) {
          motorEnabled = false;
          digitalWrite(EN_PIN, HIGH);  // Disable motor
          pStatusCharacteristic->setValue("Motor stopped");
        } else {
          motorEnabled = true;
          digitalWrite(EN_PIN, LOW);   // Enable motor
          String status = "Target speed: " + String(newSpeed, 1) + " deg/s";
          pStatusCharacteristic->setValue(status.c_str());
        }
        pStatusCharacteristic->notify();
      }
    }
};

class AccelCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      if (value.length() > 0) {
        float newAccel = atof(value.c_str());
        if (newAccel > 0) {  // Ensure acceleration is positive
          maxAcceleration = newAccel;
          String status = "Max acceleration: " + String(newAccel, 1) + " deg/s²";
          pStatusCharacteristic->setValue(status.c_str());
          pStatusCharacteristic->notify();
        }
      }
    }
};

void updateSpeed() {
  unsigned long currentTime = micros();
  if (currentTime - lastSpeedUpdate >= CONTROL_INTERVAL) {
    float deltaTime = (currentTime - lastSpeedUpdate) / 1000000.0; // Convert to seconds
    lastSpeedUpdate = currentTime;

    // Calculate maximum speed change for this interval
    float maxSpeedChange = maxAcceleration * deltaTime;
    
    // Adjust current speed towards target speed with immediate response for small changes
    float speedDiff = targetSpeed - currentSpeed;
    if (abs(speedDiff) < maxSpeedChange) {
      // If we're close to target speed, just set it directly
      currentSpeed = targetSpeed;
    } else if (speedDiff > 0) {
      currentSpeed += maxSpeedChange;
    } else {
      currentSpeed -= maxSpeedChange;
    }
  }
}

// Cached step timing variables
unsigned long lastStepTime = 0;
int currentStepDelay = MIN_STEP_DELAY;
bool stepState = false;

void step() {
  if (currentSpeed == 0 || !motorEnabled) return;
  
  unsigned long currentTime = micros();
  
  // Only recalculate step timing when speed changes
  static float lastCalculatedSpeed = 0;
  if (currentSpeed != lastCalculatedSpeed) {
    float stepsPerSecond = abs(currentSpeed) * (TOTAL_STEPS_PER_REV / 360.0);
    currentStepDelay = max(MIN_STEP_DELAY, (int)(1000000.0 / stepsPerSecond / 2));
    digitalWrite(DIR_PIN, currentSpeed > 0 ? HIGH : LOW);
    lastCalculatedSpeed = currentSpeed;
  }
  
  // Check if it's time for the next step
  if (currentTime - lastStepTime >= currentStepDelay) {
    stepState = !stepState;
    digitalWrite(STEP_PIN, stepState ? HIGH : LOW);
    lastStepTime = currentTime;
  }
}

void setup() {
  // Configure pins
  pinMode(EN_PIN, OUTPUT);
  pinMode(STEP_PIN, OUTPUT);
  pinMode(DIR_PIN, OUTPUT);
  
  digitalWrite(EN_PIN, HIGH);     // Initially disable motor
  digitalWrite(STEP_PIN, LOW);
  digitalWrite(DIR_PIN, HIGH);

  // Initialize TMC2209 UART
  SerialTMC.begin(115200, SERIAL_8N1, RX_PIN, TX_PIN);
  
  // Configure TMC2209
  driver.begin();                 // Start TMC2209
  driver.toff(5);                // Enables driver in software
  driver.rms_current(800);       // Set motor current to 800mA
  driver.microsteps(MICROSTEPS); // Set microsteps
  driver.en_spreadCycle(false);  // Enable StealthChop quiet stepping mode
  driver.pwm_autoscale(true);    // Needed for StealthChop

  // Initialize BLE
  BLEDevice::init("CameraRobot");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // Create BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create BLE Characteristics
  pSpeedCharacteristic = pService->createCharacteristic(
    SPEED_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pSpeedCharacteristic->setCallbacks(new SpeedCallbacks());

  pAccelCharacteristic = pService->createCharacteristic(
    ACCEL_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pAccelCharacteristic->setCallbacks(new AccelCallbacks());

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
  lastSpeedUpdate = micros();
}

void loop() {
  updateSpeed();
  step();
}