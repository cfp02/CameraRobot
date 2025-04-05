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
  BluetoothCharacteristic? _positionCharacteristic;
  BluetoothCharacteristic? _zeroCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;
  bool _isConnected = false;
  DateTime _lastPositionUpdate = DateTime.now();

  // Touch interface state
  final double _maxAngle = 45.0; // Maximum pan/tilt angle in degrees
  Offset? _lastTouchPosition;
  bool _isDragging = false;

  // Position update tracking
  double _pendingPan = 0;
  double _pendingTilt = 0;
  bool _hasPendingUpdate = false;

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
              _positionCharacteristic = characteristic;
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

  void _setPositions(double pan, double tilt) {
    // Always update the pending positions with the latest values
    _pendingPan = pan.clamp(-_maxAngle, _maxAngle);
    _pendingTilt = tilt.clamp(-_maxAngle, _maxAngle);
    _hasPendingUpdate = true;

    // Update the UI immediately
    setState(() {
      _position1 = _pendingTilt;
      _position2 = _pendingPan;
    });

    // Check if we can send an update
    final now = DateTime.now();
    if (now.difference(_lastPositionUpdate).inMilliseconds >= 100) {
      _sendPositionUpdate();
    }
  }

  void _sendPositionUpdate() {
    if (!_isConnected || !_hasPendingUpdate) return;

    try {
      // Round to nearest degree
      final pan = _pendingPan.roundToDouble();
      final tilt = _pendingTilt.roundToDouble();

      // Send both positions in a single message: "pan,tilt"
      String message = "${pan.toStringAsFixed(1)},${tilt.toStringAsFixed(1)}";
      _positionCharacteristic!.write(utf8.encode(message));
      _lastPositionUpdate = DateTime.now();
      _hasPendingUpdate = false;
    } catch (e) {
      setState(() => _status = "Error setting positions: ${e.toString()}");
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

  void _handleTouch(Offset position, Size size) {
    if (!_isConnected) return;

    // Convert touch position to normalized coordinates (-1 to 1)
    // Note: Y axis is inverted because screen coordinates go from top to bottom
    double normalizedX = (position.dx / size.width) * 2 - 1;
    double normalizedY = 1 - (position.dy / size.height) * 2; // Invert Y axis

    // Clamp values to -1 to 1
    normalizedX = normalizedX.clamp(-1.0, 1.0);
    normalizedY = normalizedY.clamp(-1.0, 1.0);

    // Convert to angles (-120 to 120 degrees)
    double panAngle = normalizedX * _maxAngle;
    double tiltAngle = normalizedY * _maxAngle;

    // Update positions
    _setPositions(panAngle, tiltAngle);
  }

  // Add this method to show the projection mode dialog
  void _showProjectionMode() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            color: Colors.black,
            child: Stack(
              children: [
                // Touch area
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      setState(() {
                        _isDragging = true;
                        _lastTouchPosition = details.localPosition;
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _lastTouchPosition = details.localPosition;
                      });
                      _handleTouch(
                          details.localPosition, MediaQuery.of(context).size);
                    },
                    onPanEnd: (details) {
                      setState(() {
                        _isDragging = false;
                        _lastTouchPosition = null;
                      });
                    },
                    onTapDown: (details) {
                      setState(() {
                        _lastTouchPosition = details.localPosition;
                      });
                      _handleTouch(
                          details.localPosition, MediaQuery.of(context).size);
                    },
                  ),
                ),
                // Crosshair
                Center(
                  child: Container(
                    width: 2,
                    height: 2,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                // Touch indicator
                if (_lastTouchPosition != null)
                  Positioned(
                    left: _lastTouchPosition!.dx - 10,
                    top: _lastTouchPosition!.dy - 10,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // Angle labels
                Positioned(
                  top: 8,
                  left: 8,
                  child: Text(
                    'Tilt: ${_position1.toStringAsFixed(1)}°',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Text(
                    'Pan: ${_position2.toStringAsFixed(1)}°',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
                // Close button
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Add a periodic check to send pending updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final now = DateTime.now();
      if (_hasPendingUpdate &&
          now.difference(_lastPositionUpdate).inMilliseconds >= 100) {
        _sendPositionUpdate();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Robot Control'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: _isConnected ? _setZero : null,
                          child: const Text('SET ZERO POSITION'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _showProjectionMode : null,
                          child: const Text('PROJECTION MODE'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Motor Controls
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
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
                              min: -_maxAngle,
                              max: _maxAngle,
                              divisions: (_maxAngle * 2).round(),
                              label: '${_position1.toStringAsFixed(0)}°',
                              onChanged: _isConnected
                                  ? (value) => _setPositions(_position2, value)
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: _isConnected
                                  ? () => _setPositions(_position2, 0)
                                  : null,
                              child: const Text('GO TO ZERO'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
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
                              min: -_maxAngle,
                              max: _maxAngle,
                              divisions: (_maxAngle * 2).round(),
                              label: '${_position2.toStringAsFixed(0)}°',
                              onChanged: _isConnected
                                  ? (value) => _setPositions(value, _position1)
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: _isConnected
                                  ? () => _setPositions(0, _position1)
                                  : null,
                              child: const Text('GO TO ZERO'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Global Zero Button
                    ElevatedButton(
                      onPressed:
                          _isConnected ? () => _setPositions(0, 0) : null,
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
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _setPositions(0, 0); // Return to zero when leaving screen
    widget.device.disconnect();
    super.dispose();
  }
}
