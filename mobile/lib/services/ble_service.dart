import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothDevice? device;
  BluetoothCharacteristic? textInputChar;
  BluetoothCharacteristic? morseOutputChar;
  BluetoothCharacteristic? hapticControlChar;
  BluetoothCharacteristic? deviceStatusChar;

  // UUIDs from firmware
  static const String SERVICE_UUID = "19B10000-E8F2-537E-4F6C-D104768A1214";
  static const String TEXT_INPUT_UUID = "19B10001-E8F2-537E-4F6C-D104768A1214";
  static const String MORSE_OUTPUT_UUID =
      "19B10002-E8F2-537E-4F6C-D104768A1214";
  static const String HAPTIC_CONTROL_UUID =
      "19B10003-E8F2-537E-4F6C-D104768A1214";
  static const String DEVICE_STATUS_UUID =
      "19B10004-E8F2-537E-4F6C-D104768A1214";

  // Stream controllers
  final _morseOutputController = StreamController<String>.broadcast();
  final _deviceStatusController = StreamController<int>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<String> get morseStream => _morseOutputController.stream;
  Stream<int> get deviceStatusStream => _deviceStatusController.stream;
  Stream<bool> get connectionStream => _connectionStateController.stream;

  // Device status codes
  static const int STATUS_IDLE = 0;
  static const int STATUS_PROCESSING = 1;
  static const int STATUS_PLAYING = 2;
  static const int STATUS_ERROR = 3;

  // Scanning
  Future<void> startScan() async {
    print('Starting BLE scan for MorseCodify devices');
    if (await FlutterBluePlus.isOn) {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        withServices: [Guid(SERVICE_UUID)],
      );
    }
  }

  Future<void> stopScan() async {
    print('Stopping BLE scan');
    await FlutterBluePlus.stopScan();
  }

  // Connection
  Future<void> connect(BluetoothDevice device) async {
    print('Connecting to MorseCodify device: ${device.platformName}');
    this.device = device;

    try {
      // Set up connection state listener before connecting
      device.connectionState.listen((BluetoothConnectionState state) {
        print('Connection state changed: $state');
        bool isConnected = state == BluetoothConnectionState.connected;
        _connectionStateController.add(isConnected);

        if (!isConnected) {
          // Clean up characteristics on disconnect
          textInputChar = null;
          morseOutputChar = null;
          hapticControlChar = null;
          deviceStatusChar = null;
        }
      });

      await device.connect(timeout: const Duration(seconds: 5));
      print('Connected to device');
      _connectionStateController.add(true);

      // Request MTU update for better throughput
      try {
        await device.requestMtu(512);
        print('MTU updated');
      } catch (e) {
        print('Failed to update MTU: $e');
      }

      await _discoverServices();
    } catch (e) {
      print('Error connecting to device: $e');
      _connectionStateController.add(false);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (device != null) {
      print('Disconnecting from device');
      await device!.disconnect();
      _connectionStateController.add(false);
      device = null;
      textInputChar = null;
      morseOutputChar = null;
      hapticControlChar = null;
      deviceStatusChar = null;
    }
  }

  // Service discovery
  Future<void> _discoverServices() async {
    if (device == null) return;

    print('Discovering MorseCodify services');
    List<BluetoothService> services = await device!.discoverServices();

    for (var service in services) {
      if (service.uuid.toString().toUpperCase() == SERVICE_UUID.toUpperCase()) {
        print('Found MorseCodify service');
        for (var characteristic in service.characteristics) {
          String charUuid = characteristic.uuid.toString().toUpperCase();

          if (charUuid == TEXT_INPUT_UUID.toUpperCase()) {
            print('Found text input characteristic');
            textInputChar = characteristic;
          } else if (charUuid == MORSE_OUTPUT_UUID.toUpperCase()) {
            print('Found morse output characteristic');
            morseOutputChar = characteristic;
            await _setupMorseNotifications(characteristic);
          } else if (charUuid == HAPTIC_CONTROL_UUID.toUpperCase()) {
            print('Found haptic control characteristic');
            hapticControlChar = characteristic;
          } else if (charUuid == DEVICE_STATUS_UUID.toUpperCase()) {
            print('Found device status characteristic');
            deviceStatusChar = characteristic;
            await _setupStatusNotifications(characteristic);
          }
        }
      }
    }
  }

  Future<void> _setupMorseNotifications(
      BluetoothCharacteristic characteristic) async {
    try {
      await characteristic.setNotifyValue(true);
      characteristic.onValueReceived.listen(
        (value) {
          String morse = utf8.decode(value);
          print('Received morse code: $morse');
          _morseOutputController.add(morse);
        },
        onError: (error) {
          print('Error receiving morse code: $error');
        },
        cancelOnError: false,
      );
      print('Morse notifications enabled');
    } catch (e) {
      print('Error setting up morse notifications: $e');
    }
  }

  Future<void> _setupStatusNotifications(
      BluetoothCharacteristic characteristic) async {
    try {
      await characteristic.setNotifyValue(true);
      characteristic.onValueReceived.listen(
        (value) {
          if (value.isNotEmpty) {
            int status = value[0];
            print('Received device status: $status');
            _deviceStatusController.add(status);
          }
        },
        onError: (error) {
          print('Error receiving device status: $error');
        },
        cancelOnError: false,
      );
      print('Status notifications enabled');
    } catch (e) {
      print('Error setting up status notifications: $e');
    }
  }

  // Text to Morse conversion
  Future<void> sendText(String text) async {
    if (textInputChar == null) {
      print('Cannot send text: Text input characteristic not available');
      return;
    }

    try {
      await textInputChar!.write(utf8.encode(text));
      print('Sent text: $text');
    } catch (e) {
      print('Error sending text: $e');
      rethrow;
    }
  }

  // Haptic control
  Future<void> setHapticIntensity(int intensity) async {
    if (hapticControlChar == null) {
      print(
          'Cannot set haptic intensity: Haptic control characteristic not available');
      return;
    }

    try {
      await hapticControlChar!.write([intensity]);
      print('Set haptic intensity: $intensity');
    } catch (e) {
      print('Error setting haptic intensity: $e');
      rethrow;
    }
  }

  void dispose() {
    print('Disposing BLE service');
    disconnect();
    _morseOutputController.close();
    _deviceStatusController.close();
    _connectionStateController.close();
  }
}
