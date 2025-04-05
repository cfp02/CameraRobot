#include <Arduino.h>
#include <TMCStepper.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <AccelStepper.h>

// Pin Definitions for Motor 1 (using UART1)
#define EN_PIN_1     1    // Enable pin (GPIO1)
#define STEP_PIN_1   2    // Step pin (GPIO2)
#define DIR_PIN_1    3    // Direction pin (GPIO3)
#define RX_PIN_1     8    // UART1 RX pin (GPIO8)
#define TX_PIN_1     7    // UART1 TX pin (GPIO6)

// Pin Definitions for Motor 2 (using UART0)
#define EN_PIN_2     4    // Enable pin (GPIO4)
#define STEP_PIN_2   5    // Step pin (GPIO5)
#define DIR_PIN_2    6    // Direction pin (GPIO7)
#define RX_PIN_2     44   // UART0 RX pin (GPIO44)
#define TX_PIN_2     43   // UART0 TX pin (GPIO43)

#define R_SENSE    0.11f // R_sense resistor value in ohms
#define DRIVER_ADDRESS 0b00   // TMC2209 Driver address according to MS1 and MS2

// Motor Configuration
#define STEPS_PER_REV 200      // 1.8 degree steps
#define MICROSTEPS 16     
#define GEAR_RATIO_1 (60.0/18.0) // 18:60 reduction for motor 1 (3.33:1)
#define GEAR_RATIO_2 (170.0/18.0) // 18:170 reduction for motor 2 (9.44:1)
#define TOTAL_STEPS_PER_REV_1 (STEPS_PER_REV * MICROSTEPS * GEAR_RATIO_1)
#define TOTAL_STEPS_PER_REV_2 (STEPS_PER_REV * MICROSTEPS * GEAR_RATIO_2)
#define DEFAULT_MAX_SPEED 90  // Default maximum speed in degrees per second
#define DEFAULT_ACCELERATION 5000  // Default acceleration in steps per second squared

// BLE UUIDs
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define POSITION_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"  // Combined pan/tilt
#define ZERO_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define STATUS_CHAR_UUID "5b818d26-7c11-4f24-b87f-4f8a8cc974eb"

// Create TMC2209 UART instances
HardwareSerial SerialTMC1(1);  // Use UART1 for motor 1
HardwareSerial SerialTMC2(0);  // Use UART0 for motor 2
TMC2209Stepper driver1 = TMC2209Stepper(&SerialTMC1, R_SENSE, DRIVER_ADDRESS);
TMC2209Stepper driver2 = TMC2209Stepper(&SerialTMC2, R_SENSE, DRIVER_ADDRESS);

// Global variables
BLEServer* pServer = NULL;
BLEService* pService = NULL;
BLECharacteristic* pPositionCharacteristic = NULL;
BLECharacteristic* pZeroCharacteristic = NULL;
BLECharacteristic* pStatusCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Position tracking
long targetPosition1 = 0;
long targetPosition2 = 0;
long currentPosition1 = 0;
long currentPosition2 = 0;

// Speed and acceleration tracking
float maxSpeed1 = DEFAULT_MAX_SPEED * (TOTAL_STEPS_PER_REV_1 / 360.0);
float maxSpeed2 = DEFAULT_MAX_SPEED * (TOTAL_STEPS_PER_REV_2 / 360.0);
float acceleration1 = DEFAULT_ACCELERATION;
float acceleration2 = DEFAULT_ACCELERATION;

// Motor objects
AccelStepper stepper1(AccelStepper::DRIVER, STEP_PIN_1, DIR_PIN_1);
AccelStepper stepper2(AccelStepper::DRIVER, STEP_PIN_2, DIR_PIN_2);

// BLE callbacks
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("Device connected");
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("Device disconnected");
        // Stop motors when disconnected
        stepper1.stop();
        stepper2.stop();
        stepper1.disableOutputs();
        stepper2.disableOutputs();
    }
};

class PositionCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value.length() > 0) {
            Serial.print("Received position command: ");
            Serial.println(value.c_str());
            
            // Parse the combined pan/tilt message
            size_t commaPos = value.find(',');
            if (commaPos != std::string::npos) {
                std::string panStr = value.substr(0, commaPos);
                std::string tiltStr = value.substr(commaPos + 1);
                
                float panDegrees = atof(panStr.c_str());
                float tiltDegrees = atof(tiltStr.c_str());
                
                Serial.print("Parsed pan: ");
                Serial.print(panDegrees);
                Serial.print(" tilt: ");
                Serial.println(tiltDegrees);
                
                // Convert degrees to steps for each motor
                targetPosition1 = tiltDegrees * (TOTAL_STEPS_PER_REV_1 / 360.0);
                targetPosition2 = panDegrees * (TOTAL_STEPS_PER_REV_2 / 360.0);
                
                Serial.print("Target steps - Motor 1: ");
                Serial.print(targetPosition1);
                Serial.print(" Motor 2: ");
                Serial.println(targetPosition2);
                
                stepper1.moveTo(targetPosition1);
                stepper2.moveTo(targetPosition2);
                stepper1.enableOutputs();
                stepper2.enableOutputs();
            } else {
                Serial.println("Invalid position format");
            }
        }
    }
};

class ZeroCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value == "zero") {
            // Set current position as zero for both motors
            stepper1.setCurrentPosition(0);
            stepper2.setCurrentPosition(0);
            currentPosition1 = 0;
            currentPosition2 = 0;
            targetPosition1 = 0;
            targetPosition2 = 0;
            
            // Update status
            String status = "Zero position set";
            pStatusCharacteristic->setValue(status.c_str());
            pStatusCharacteristic->notify();
            
            // Ensure motors are enabled after zeroing
            stepper1.enableOutputs();
            stepper2.enableOutputs();
        }
    }
};

class SpeedCallbacks1: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value.length() > 0) {
            float speed = atof(value.c_str());
            // Limit speed to prevent skipping
            speed = min(speed, 90.0f);  // Max 90 degrees per second
            maxSpeed1 = speed * (TOTAL_STEPS_PER_REV_1 / 360.0);  // Convert degrees/sec to steps/sec
            acceleration1 = maxSpeed1 * 2;  // Set acceleration proportional to max speed
            stepper1.setMaxSpeed(maxSpeed1);
            stepper1.setAcceleration(acceleration1);
        }
    }
};

class SpeedCallbacks2: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value.length() > 0) {
            float speed = atof(value.c_str());
            // Limit speed to prevent skipping
            speed = min(speed, 90.0f);  // Max 90 degrees per second
            maxSpeed2 = speed * (TOTAL_STEPS_PER_REV_2 / 360.0);  // Convert degrees/sec to steps/sec
            acceleration2 = maxSpeed2 * 2;  // Set acceleration proportional to max speed
            stepper2.setMaxSpeed(maxSpeed2);
            stepper2.setAcceleration(acceleration2);
        }
    }
};

void setup() {
    // Initialize Serial for debugging
    Serial.begin(115200);
    Serial.println("Camera Robot Starting...");
    
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
    pService = pServer->createService(SERVICE_UUID);

    // Create BLE Characteristics
    pPositionCharacteristic = pService->createCharacteristic(
        POSITION_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pPositionCharacteristic->setCallbacks(new PositionCallbacks());
    pPositionCharacteristic->addDescriptor(new BLE2902());

    pZeroCharacteristic = pService->createCharacteristic(
        ZERO_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pZeroCharacteristic->setCallbacks(new ZeroCallbacks());
    pZeroCharacteristic->addDescriptor(new BLE2902());

    pStatusCharacteristic = pService->createCharacteristic(
        STATUS_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
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

    // Initialize stepper motors
    pinMode(EN_PIN_1, OUTPUT);
    pinMode(EN_PIN_2, OUTPUT);
    digitalWrite(EN_PIN_1, LOW);  // Enable motor 1
    digitalWrite(EN_PIN_2, LOW);  // Enable motor 2

    stepper1.setMaxSpeed(DEFAULT_MAX_SPEED * (TOTAL_STEPS_PER_REV_1 / 360.0));
    stepper1.setAcceleration(DEFAULT_ACCELERATION);
    stepper1.setEnablePin(EN_PIN_1);
    stepper1.setPinsInverted(false, false, true);
    stepper1.enableOutputs();  // Explicitly enable motor 1

    stepper2.setMaxSpeed(DEFAULT_MAX_SPEED * (TOTAL_STEPS_PER_REV_2 / 360.0));
    stepper2.setAcceleration(DEFAULT_ACCELERATION);
    stepper2.setEnablePin(EN_PIN_2);
    stepper2.setPinsInverted(false, false, true);
    stepper2.enableOutputs();  // Explicitly enable motor 2

    // Set initial positions
    stepper1.setCurrentPosition(0);
    stepper2.setCurrentPosition(0);

    Serial.println("Setup complete!");
}

void loop() {
    // Handle BLE connection
    if (!deviceConnected && oldDeviceConnected) {
        delay(500);
        pServer->startAdvertising();
        oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }

    // Run steppers
    stepper1.run();
    stepper2.run();

    // Update current positions
    currentPosition1 = stepper1.currentPosition() / (TOTAL_STEPS_PER_REV_1 / 360.0);
    currentPosition2 = stepper2.currentPosition() / (TOTAL_STEPS_PER_REV_2 / 360.0);

    // Send status update every 100ms
    static unsigned long lastStatusUpdate = 0;
    if (millis() - lastStatusUpdate >= 100) {
        String status = "Pos1: " + String(currentPosition1) + "° Pos2: " + String(currentPosition2) + "°";
        pStatusCharacteristic->setValue(status.c_str());
        pStatusCharacteristic->notify();
        lastStatusUpdate = millis();
    }
}