import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class MorseScreen extends StatefulWidget {
  const MorseScreen({super.key});

  @override
  State<MorseScreen> createState() => _MorseScreenState();
}

class _MorseScreenState extends State<MorseScreen> {
  final TextEditingController _textController = TextEditingController();
  final BleService _bleService = BleService();
  String _morseOutput = '';
  int _deviceStatus = BleService.STATUS_IDLE;
  double _hapticIntensity = 0.5; // 0.0 to 1.0

  StreamSubscription? _morseSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _setupStreams();
  }

  void _setupStreams() {
    _morseSubscription = _bleService.morseStream.listen(
      (morse) {
        if (mounted) {
          setState(() {
            _morseOutput = morse;
          });
        }
      },
      onError: (error) {
        print('Error receiving morse code: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error receiving morse code: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );

    _statusSubscription = _bleService.deviceStatusStream.listen(
      (status) {
        if (mounted) {
          setState(() {
            _deviceStatus = status;
          });
        }
      },
      onError: (error) {
        print('Error receiving device status: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error receiving device status: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );

    // Set up connection state monitoring
    _connectionSubscription = _bleService.connectionStream.listen(
      (isConnected) {
        if (!isConnected && mounted) {
          // Cancel any existing reconnect timer
          _reconnectTimer?.cancel();

          // Show disconnection message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device disconnected'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );

          // Start a 5-second timer before navigating back
          _reconnectTimer = Timer(const Duration(seconds: 5), () {
            if (mounted && Navigator.canPop(context)) {
              Navigator.pushReplacementNamed(context, '/');
            }
          });
        }
      },
      onError: (error) {
        print('Error monitoring connection: $error');
      },
    );
  }

  String _getStatusText() {
    switch (_deviceStatus) {
      case BleService.STATUS_IDLE:
        return 'Ready';
      case BleService.STATUS_PROCESSING:
        return 'Converting...';
      case BleService.STATUS_PLAYING:
        return 'Playing Morse Code';
      case BleService.STATUS_ERROR:
        return 'Error';
      default:
        return 'Unknown';
    }
  }

  Future<void> _sendText() async {
    if (_textController.text.isEmpty) return;

    try {
      await _bleService.sendText(_textController.text);
      // Clear text field after successful send
      _textController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send text: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateHapticIntensity(double value) async {
    setState(() {
      _hapticIntensity = value;
    });

    try {
      // Convert 0.0-1.0 to 0-255 for BLE
      int intensity = (value * 255).round();
      await _bleService.setHapticIntensity(intensity);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update haptic intensity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MorseCodify'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status indicator
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: _deviceStatus == BleService.STATUS_ERROR
                    ? Colors.red.shade100
                    : Colors.green.shade100,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                'Status: ${_getStatusText()}',
                style: TextStyle(
                  color: _deviceStatus == BleService.STATUS_ERROR
                      ? Colors.red.shade900
                      : Colors.green.shade900,
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // Text input
            TextField(
              controller: _textController,
              decoration: InputDecoration(
                labelText: 'Enter Text',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendText,
                ),
              ),
              onSubmitted: (_) => _sendText(),
            ),
            const SizedBox(height: 16.0),

            // Morse code output
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Morse Code:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.0,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    _morseOutput.isEmpty ? 'No morse code yet' : _morseOutput,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18.0,
                      color: _morseOutput.isEmpty
                          ? Colors.grey.shade600
                          : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24.0),

            // Haptic intensity control
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Haptic Intensity',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.vibration, size: 20.0),
                    Expanded(
                      child: Slider(
                        value: _hapticIntensity,
                        onChanged: _updateHapticIntensity,
                        divisions: 10,
                        label: '${(_hapticIntensity * 100).round()}%',
                      ),
                    ),
                    const Icon(Icons.vibration, size: 28.0),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _morseSubscription?.cancel();
    _statusSubscription?.cancel();
    _connectionSubscription?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
