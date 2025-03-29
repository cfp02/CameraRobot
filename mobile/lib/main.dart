import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/camera_robot_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera Robot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BluetoothScanScreen(),
    );
  }
}

class BluetoothScanScreen extends StatefulWidget {
  const BluetoothScanScreen({super.key});

  @override
  State<BluetoothScanScreen> createState() => _BluetoothScanScreenState();
}

class _BluetoothScanScreenState extends State<BluetoothScanScreen> {
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    if (await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted &&
        await Permission.location.request().isGranted) {
      _startScan();
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _scanResults = [];
      _isScanning = true;
    });

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 4),
      androidUsesFineLocation: true,
    );

    setState(() {
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Robot'),
      ),
      body: RefreshIndicator(
        onRefresh: _startScan,
        child: ListView.builder(
          itemCount: _scanResults.length,
          itemBuilder: (context, index) {
            final result = _scanResults[index];
            final device = result.device;
            final name =
                device.name.isNotEmpty ? device.name : "Unknown Device";

            // Only show the CameraRobot device
            if (name != "CameraRobot") return const SizedBox.shrink();

            return ListTile(
              title: Text(name),
              subtitle: Text(device.id.id),
              trailing: Text("${result.rssi} dBm"),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CameraRobotScreen(device: device),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? null : _startScan,
        child: Icon(_isScanning ? Icons.hourglass_empty : Icons.refresh),
      ),
    );
  }
}
