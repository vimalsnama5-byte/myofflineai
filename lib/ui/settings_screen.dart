import 'package:flutter/material.dart';

import '../models/model_catalog.dart';
import '../services/assistant_controller.dart';
import '../services/model_manager.dart';
import 'setup_screen.dart';

/// Model management + memory controls.
class SettingsScreen extends StatefulWidget {
  final AssistantController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<ModelKind, String> _sel = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _sel = await ModelManager.instance.selection();
    if (mounted) setState(() {});
  }

  String _kindLabel(ModelKind k) => switch (k) {
        ModelKind.llm => 'AI brain',
        ModelKind.stt => 'Speech recognition',
        ModelKind.tts => 'Voice',
        ModelKind.avatar => 'Avatar',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final kind in ModelKind.values)
            ListTile(
              title: Text(_kindLabel(kind)),
              subtitle: Text(_sel[kind] == null
                  ? 'not installed'
                  : specById(kind, _sel[kind]!).name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final id = _sel[kind];
                  if (id == null) return;
                  await ModelManager.instance
                      .delete(specById(kind, id));
                  await _load();
                },
              ),
            ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('Clear conversation memory'),
            subtitle: const Text('Forget all past chats'),
            onTap: () async {
              await widget.controller.clearMemory();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Memory cleared')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Model setup'),
            subtitle: const Text('Re-open the download screen'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SetupScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Debug logs'),
            subtitle: Text('${widget.controller.logs.length} entries'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _LogsScreen(logs: widget.controller.logs),
            )),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Packet AI runs fully offline: Whisper.cpp for listening, '
              'llama.cpp for thinking, Piper for speaking, and a GLB avatar '
              'rendered by Filament.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogsScreen extends StatelessWidget {
  final List<String> logs;
  const _LogsScreen({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug logs')),
      body: logs.isEmpty
          ? const Center(child: Text('No log entries yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  logs[logs.length - 1 - i],
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
    );
  }
}
