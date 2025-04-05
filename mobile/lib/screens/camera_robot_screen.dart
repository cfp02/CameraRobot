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
  double _position1 = 0;
  double _position2 = 0;
  String _status = "Connecting...";
  BluetoothCharacteristic? _positionCharacteristic1;
  BluetoothCharacteristic? _positionCharacteristic2;
  BluetoothCharacteristic? _zeroCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;
  bool _isConnected = false;
  DateTime _lastPositionUpdate1 = DateTime.now();
  DateTime _lastPositionUpdate2 = DateTime.now();

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
              _positionCharacteristic1 = characteristic;
            } else if (characteristic.uuid.toString() ==
                "beb5483e-36e1-4688-b7f5-ea07361b26a9") {
              _positionCharacteristic2 = characteristic;
            } else if (characteristic.uuid.toString() ==
                "beb5483e-36e1-4688-b7f5-ea07361b26aa") {
              _zeroCharacteristic = characteristic;
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

  void _setPosition1(double position) {
    // Only send updates every 50ms
    final now = DateTime.now();
    if (now.difference(_lastPositionUpdate1).inMilliseconds >= 50) {
      position = position.clamp(-360, 360);
      // Round to nearest degree
      position = position.roundToDouble();

      setState(() => _position1 = position);

      if (_positionCharacteristic1 != null) {
        try {
          _positionCharacteristic1!.write(utf8.encode(position.toString()));
          _lastPositionUpdate1 = now;
        } catch (e) {
          setState(() => _status = "Error setting position 1: ${e.toString()}");
        }
      }
    }
  }

  void _setPosition2(double position) {
    // Only send updates every 50ms
    final now = DateTime.now();
    if (now.difference(_lastPositionUpdate2).inMilliseconds >= 50) {
      position = position.clamp(-360, 360);
      // Round to nearest degree
      position = position.roundToDouble();

      setState(() => _position2 = position);

      if (_positionCharacteristic2 != null) {
        try {
          _positionCharacteristic2!.write(utf8.encode(position.toString()));
          _lastPositionUpdate2 = now;
        } catch (e) {
          setState(() => _status = "Error setting position 2: ${e.toString()}");
        }
      }
    }
  }

  void _setZero() {
    if (_zeroCharacteristic != null) {
      try {
        _zeroCharacteristic!.write(utf8.encode("zero"));
        setState(() {
          _position1 = 0;
          _position2 = 0;
        });
      } catch (e) {
        setState(() => _status = "Error setting zero: ${e.toString()}");
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
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isConnected ? _setZero : null,
                      child: const Text('SET ZERO POSITION'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
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
                      'Motor 1 Position: ${_position1.toStringAsFixed(0)}°',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Slider(
                      value: _position1,
                      min: -360,
                      max: 360,
                      divisions: 720,
                      label: '${_position1.toStringAsFixed(0)}°',
                      onChanged: _isConnected ? _setPosition1 : null,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isConnected ? () => _setPosition1(0) : null,
                      child: const Text('GO TO ZERO'),
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
                      'Motor 2 Position: ${_position2.toStringAsFixed(0)}°',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Slider(
                      value: _position2,
                      min: -360,
                      max: 360,
                      divisions: 720,
                      label: '${_position2.toStringAsFixed(0)}°',
                      onChanged: _isConnected ? _setPosition2 : null,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isConnected ? () => _setPosition2(0) : null,
                      child: const Text('GO TO ZERO'),
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
            // Global Zero Button
            ElevatedButton(
              onPressed: _isConnected
                  ? () {
                      _setPosition1(0);
                      _setPosition2(0);
                    }
                  : null,
              child: const Text('GO TO ZERO (BOTH MOTORS)'),
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
    _setPosition1(0); // Return to zero when leaving screen
    _setPosition2(0); // Return to zero when leaving screen
    widget.device.disconnect();
    super.dispose();
  }
}
