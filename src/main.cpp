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
#define MIN_STEP_DELAY 30      // Reduced from 50 to 30 microseconds since we have fewer steps

// BLE UUIDs
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SPEED_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define STATUS_CHAR_UUID   "5b818d26-7c11-4f24-b87f-4f8a8cc974eb"

// Create TMC2209 UART instance
HardwareSerial SerialTMC(1);  // Use hardware serial port 1
TMC2209Stepper driver = TMC2209Stepper(&SerialTMC, R_SENSE, DRIVER_ADDRESS);  // Create TMC driver

// BLE globals
BLEServer* pServer = NULL;
BLECharacteristic* pSpeedCharacteristic = NULL;
BLECharacteristic* pStatusCharacteristic = NULL;
bool deviceConnected = false;
float currentSpeed = 0;  // in degrees per second
bool motorEnabled = false;

// BLE callbacks
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      pStatusCharacteristic->setValue("Connected - 8 microsteps mode");
      pStatusCharacteristic->notify();
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      // Stop motor on disconnect for safety
      currentSpeed = 0;
      motorEnabled = false;
      digitalWrite(EN_PIN, HIGH);  // Disable motor
      pStatusCharacteristic->setValue("Disconnected");
      pStatusCharacteristic->notify();
      // Restart advertising
      BLEDevice::startAdvertising();
    }
};

class SpeedCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      if (value.length() > 0) {
        float degreesPerSecond = atof(value.c_str());
        currentSpeed = degreesPerSecond;
        
        if (degreesPerSecond == 0) {
          motorEnabled = false;
          digitalWrite(EN_PIN, HIGH);  // Disable motor
          pStatusCharacteristic->setValue("Motor stopped");
        } else {
          motorEnabled = true;
          digitalWrite(EN_PIN, LOW);   // Enable motor
          String status = "Speed: " + String(degreesPerSecond, 1) + " deg/s (8 μsteps)";
          pStatusCharacteristic->setValue(status.c_str());
        }
        pStatusCharacteristic->notify();
      }
    }
};

void setSpeed(float degreesPerSecond) {
  if (degreesPerSecond == 0 || !motorEnabled) return;
  
  // Convert degrees/second to step timing
  // steps/second = (degrees/second) * (total_steps/360_degrees)
  float stepsPerSecond = abs(degreesPerSecond) * (TOTAL_STEPS_PER_REV / 360.0);
  int delayus = max(MIN_STEP_DELAY, (int)(1000000.0 / stepsPerSecond / 2));
  
  digitalWrite(DIR_PIN, degreesPerSecond > 0 ? HIGH : LOW);
  digitalWrite(STEP_PIN, HIGH);
  delayMicroseconds(delayus);
  digitalWrite(STEP_PIN, LOW);
  delayMicroseconds(delayus);
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
  driver.microsteps(MICROSTEPS); // Set to 8 microsteps
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

  pStatusCharacteristic->setValue("Ready - 8 microsteps mode");
}

void loop() {
  setSpeed(currentSpeed);
}