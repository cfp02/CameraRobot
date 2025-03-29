import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';

// Debouncer class to limit update rate
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer(
      {this.delay = const Duration(
          milliseconds: 250)}); // Changed to 250ms (4 updates/second)

  void run(Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

class CameraRobotScreen extends StatefulWidget {
  final BluetoothDevice device;

  const CameraRobotScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<CameraRobotScreen> createState() => _CameraRobotScreenState();
}

class _CameraRobotScreenState extends State<CameraRobotScreen> {
  double _speed = 0;
  double _displaySpeed = 0;
  String _status = "Connecting...";
  BluetoothCharacteristic? _speedCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;
  bool _isConnected = false;
  final _debouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    _speed = 0;
    _displaySpeed = 0;
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
              _speedCharacteristic = characteristic;
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

  Future<void> _setSpeed(double speed) async {
    // Clamp the speed to our min/max range
    speed = speed.clamp(-90, 90);

    if (_speedCharacteristic != null) {
      try {
        await _speedCharacteristic!.write(utf8.encode(speed.toString()));
        setState(() => _speed = speed);
      } catch (e) {
        setState(() => _status = "Error setting speed: ${e.toString()}");
      }
    }
  }

  void _onSliderChanged(double newSpeed) {
    // Clamp the speed to our min/max range
    newSpeed = newSpeed.clamp(-90, 90);

    // Update display immediately for smooth UI
    setState(() => _displaySpeed = newSpeed);

    // Debounce the actual BLE message
    _debouncer.run(() {
      if (_displaySpeed != _speed) {
        _setSpeed(_displaySpeed);
      }
    });
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
                    if (_displaySpeed != 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Time for 90°: ${(90 / _displaySpeed.abs()).toStringAsFixed(1)}s',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Speed: ${_displaySpeed.toStringAsFixed(1)}°/s',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Slider(
              value: _displaySpeed,
              min: -90,
              max: 90,
              divisions: 180,
              label: '${_displaySpeed.toStringAsFixed(1)}°/s',
              onChanged: _isConnected ? _onSliderChanged : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isConnected ? () => _setSpeed(0) : null,
              child: const Text('STOP'),
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
    _setSpeed(0); // Stop motor when leaving screen
    _debouncer.dispose(); // Clean up the debouncer
    widget.device.disconnect();
    super.dispose();
  }
}
