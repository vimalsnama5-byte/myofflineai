import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'services/model_manager.dart';
import 'ui/crash_screen.dart';
import 'ui/home_screen.dart';
import 'ui/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sherpa.initBindings();
  runApp(const PacketAiApp());
}

class PacketAiApp extends StatelessWidget {
  const PacketAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Packet AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: FutureBuilder<({bool installed, bool crashed, File marker, File? log})>(
        future: () async {
          final (marker, log) = await CrashScreen.detect();
          return (
            installed: await ModelManager.instance.allInstalled,
            crashed: await marker.exists(),
            marker: marker,
            log: log,
          );
        }(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done ||
              snap.data == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final d = snap.data!;
          if (d.installed && d.crashed) {
            return CrashScreen(markerFile: d.marker, logFile: d.log);
          }
          return d.installed ? const HomeScreen() : const SetupScreen();
        },
      ),
    );
  }
}
