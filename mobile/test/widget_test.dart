import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mobile/screens/camera_robot_screen.dart';

void main() {
  testWidgets('CameraRobot slider test', (WidgetTester tester) async {
    // Create a mock BluetoothDevice
    final mockDevice = BluetoothDevice.fromId('mock_id');

    // Build our app and trigger a frame.
    await tester.pumpWidget(MaterialApp(
      home: CameraRobotScreen(device: mockDevice),
    ));

    // Verify slider exists
    expect(find.byType(Slider), findsOneWidget);

    // Test slider with valid values
    final Slider slider = tester.widget(find.byType(Slider));
    expect(slider.min, equals(-90));
    expect(slider.max, equals(90));
    expect(slider.value, equals(0)); // Initial value

    // Verify stop button exists
    expect(find.text('STOP'), findsOneWidget);
  });
}
