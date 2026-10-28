import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'home_screen.dart';

/// Shown when the previous run left an `.init_in_progress` marker —
/// meaning the app died during startup. Displays the persisted log so
/// the crash can be diagnosed, plus a retry button.
class CrashScreen extends StatelessWidget {
  final File markerFile;
  final File? logFile;
  const CrashScreen({super.key, required this.markerFile, this.logFile});

  Future<void> _retry(BuildContext context) async {
    try {
      await markerFile.delete();
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Startup crashed')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'The app closed during startup last time. The log below shows '
              'where it got — share it to help diagnose.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: logFile == null
                    ? const Text('No log file found')
                    : FutureBuilder<String>(
                        future: logFile!.readAsString(),
                        builder: (context, snap) => SingleChildScrollView(
                          child: Text(
                            snap.data ?? 'Reading…',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final text = logFile != null && await logFile!.exists()
                          ? await logFile!.readAsString()
                          : 'no log';
                      await Clipboard.setData(ClipboardData(text: text));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy log'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _retry(context),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Resolves the marker/log files used to detect a previous crash.
  static Future<(File, File?)> detect() async {
    final docs = await getApplicationDocumentsDirectory();
    final marker = File('${docs.path}/.init_in_progress');
    final log = File('${docs.path}/packet_ai.log');
    return (marker, await log.exists() ? log : null);
  }
}
