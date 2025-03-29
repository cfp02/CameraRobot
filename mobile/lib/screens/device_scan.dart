import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final BleService _bleService = BleService();
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStartScan();
  }

  Future<void> _checkPermissionsAndStartScan() async {
    // Request permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Check if all permissions are granted
    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (allGranted) {
      await _startScan();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth and Location permissions are required'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    try {
      // Cancel existing subscription if any
      await _scanSubscription?.cancel();

      // Set up new subscription
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _scanResults = results;
          });
        }
      }, onError: (e) {
        print('Error during scan: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Scan error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });

      await _bleService.startScan();
    } catch (e) {
      print('Error starting scan: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start scan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    // Stop scanning after timeout
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await _bleService.connect(device);
      if (mounted) {
        // Navigate to Morse screen after successful connection
        Navigator.pushReplacementNamed(context, '/morse');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDeviceList() {
    if (_scanResults.isEmpty) {
      return Center(
        child: _isScanning
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No MorseCodify devices found'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _checkPermissionsAndStartScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan Again'),
                  ),
                ],
              ),
      );
    }

    return ListView.builder(
      itemCount: _scanResults.length,
      itemBuilder: (context, index) {
        final result = _scanResults[index];
        final device = result.device;
        final name = device.platformName;
        final rssi = result.rssi;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.bluetooth),
            title: Text(name.isNotEmpty ? name : 'Unknown Device'),
            subtitle: Text('Signal Strength: $rssi dBm'),
            trailing: ElevatedButton(
              onPressed: () => _connectToDevice(device),
              child: const Text('Connect'),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MorseCodify'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Available Devices',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(
            child: _buildDeviceList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? null : _checkPermissionsAndStartScan,
        child: Icon(_isScanning ? Icons.hourglass_empty : Icons.refresh),
      ),
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _bleService.stopScan();
    super.dispose();
  }
}
