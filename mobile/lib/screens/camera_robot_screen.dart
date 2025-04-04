import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';

class CameraRobotScreen extends StatefulWidget {
  final BluetoothDevice device;

  const CameraRobotScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<CameraRobotScreen> createState() => _CameraRobotScreenState();
}

class _CameraRobotScreenState extends State<CameraRobotScreen> {
  double _speed1 = 0;
  double _speed2 = 0;
  String _status = "Connecting...";
  BluetoothCharacteristic? _speedCharacteristic1;
  BluetoothCharacteristic? _speedCharacteristic2;
  BluetoothCharacteristic? _statusCharacteristic;
  bool _isConnected = false;
  DateTime _lastSpeedUpdate1 = DateTime.now();
  DateTime _lastSpeedUpdate2 = DateTime.now();

  @override
  void initState() {
    super.initState();
    _connectToDevice();
  }

  Future<void> _connectToDevice() async {
    try {
      await widget.device.connect();
      setState(() => _status = "Connected, discovering services...");

      List<BluetoothService> services = await widget.device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == "4fafc201-1fb5-459e-8fcc-c5c9c331914b") {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() ==
                "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
              _speedCharacteristic1 = characteristic;
            } else if (characteristic.uuid.toString() ==
                "beb5483e-36e1-4688-b7f5-ea07361b26a9") {
              _speedCharacteristic2 = characteristic;
            } else if (characteristic.uuid.toString() ==
                "5b818d26-7c11-4f24-b87f-4f8a8cc974eb") {
              _statusCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              characteristic.value.listen((value) {
                if (value.isNotEmpty) {
                  setState(() => _status = utf8.decode(value));
                }
              });
            }
          }
        }
      }

      setState(() => _isConnected = true);
    } catch (e) {
      setState(() => _status = "Error: ${e.toString()}");
    }
  }

  void _setSpeed1(double speed) {
    // Only send updates every 50ms and round to nearest 5 degrees/sec
    final now = DateTime.now();
    if (now.difference(_lastSpeedUpdate1).inMilliseconds >= 50) {
      speed = speed.clamp(-90, 90);
      // Round to nearest 5 degrees/sec
      speed = (speed / 5).round() * 5.0;

      setState(() => _speed1 = speed);

      if (_speedCharacteristic1 != null) {
        try {
          _speedCharacteristic1!.write(utf8.encode(speed.toString()));
          _lastSpeedUpdate1 = now;
        } catch (e) {
          setState(() => _status = "Error setting speed 1: ${e.toString()}");
        }
      }
    }
  }

  void _setSpeed2(double speed) {
    // Only send updates every 50ms and round to nearest 5 degrees/sec
    final now = DateTime.now();
    if (now.difference(_lastSpeedUpdate2).inMilliseconds >= 50) {
      speed = speed.clamp(-90, 90);
      // Round to nearest 5 degrees/sec
      speed = (speed / 5).round() * 5.0;

      setState(() => _speed2 = speed);

      if (_speedCharacteristic2 != null) {
        try {
          _speedCharacteristic2!.write(utf8.encode(speed.toString()));
          _lastSpeedUpdate2 = now;
        } catch (e) {
          setState(() => _status = "Error setting speed 2: ${e.toString()}");
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Robot Control'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Status: $_status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Motor 1 Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Motor 1 Speed: ${_speed1.toStringAsFixed(0)}°/s',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (_speed1 != 0) ...[
                      Text(
                        'Time for 90°: ${(90 / _speed1.abs()).toStringAsFixed(1)}s',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Slider(
                      value: _speed1,
                      min: -90,
                      max: 90,
                      divisions: 36,
                      label: '${_speed1.toStringAsFixed(0)}°/s',
                      onChanged: _isConnected ? _setSpeed1 : null,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isConnected ? () => _setSpeed1(0) : null,
                      child: const Text('STOP MOTOR 1'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Motor 2 Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Motor 2 Speed: ${_speed2.toStringAsFixed(0)}°/s',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (_speed2 != 0) ...[
                      Text(
                        'Time for 90°: ${(90 / _speed2.abs()).toStringAsFixed(1)}s',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Slider(
                      value: _speed2,
                      min: -90,
                      max: 90,
                      divisions: 36,
                      label: '${_speed2.toStringAsFixed(0)}°/s',
                      onChanged: _isConnected ? _setSpeed2 : null,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isConnected ? () => _setSpeed2(0) : null,
                      child: const Text('STOP MOTOR 2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Global Stop Button
            ElevatedButton(
              onPressed: _isConnected
                  ? () {
                      _setSpeed1(0);
                      _setSpeed2(0);
                    }
                  : null,
              child: const Text('STOP ALL MOTORS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _setSpeed1(0); // Stop motor 1 when leaving screen
    _setSpeed2(0); // Stop motor 2 when leaving screen
    widget.device.disconnect();
    super.dispose();
  }
}
