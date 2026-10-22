import 'package:flutter/material.dart';

import '../models/model_catalog.dart';
import '../services/assistant_controller.dart';
import '../services/model_manager.dart';
import 'setup_screen.dart';

/// Model management + memory + language controls.
class SettingsScreen extends StatefulWidget {
  final AssistantController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<ModelKind, String> _sel = {};
  final Map<String, bool> _installed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _sel = await ModelManager.instance.selection();
    for (final kind in ModelKind.values) {
      for (final spec in specsFor(kind)) {
        _installed[spec.id] =
            await ModelManager.instance.isInstalled(spec);
      }
    }
    if (mounted) setState(() {});
  }

  String _kindLabel(ModelKind k) => switch (k) {
        ModelKind.llm => 'AI brain',
        ModelKind.stt => 'Speech recognition (STT)',
        ModelKind.tts => 'Voice (TTS)',
        ModelKind.avatar => 'Avatar',
      };

  Future<void> _selectSpec(ModelKind kind, String id) async {
    if (_installed[id] != true) {
      // Not downloaded yet — send them to the setup screen.
      await ModelManager.instance.select(kind, id);
      if (!mounted) return;
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SetupScreen()));
      return;
    }
    await ModelManager.instance.select(kind, id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Switched — restart the app to load the new model')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Assistant language',
              style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: widget.controller.language,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'ta', child: Text('தமிழ் (Tamil)')),
            ],
            onChanged: (v) async {
              if (v != null) await widget.controller.setLanguage(v);
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Tamil needs the multilingual Whisper model (STT) and a '
            'Tamil Piper voice below.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const Divider(height: 32),
          for (final kind in ModelKind.values) ...[
            Text(_kindLabel(kind),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _sel[kind],
              isExpanded: true,
              items: [
                for (final spec in specsFor(kind))
                  DropdownMenuItem(
                    value: spec.id,
                    child: Text(
                        '${spec.name}${_installed[spec.id] == true ? '' : '  (not downloaded)'}'),
                  ),
                if (kind == ModelKind.avatar &&
                    _sel[kind] == kCustomAvatarSpec.id)
                  DropdownMenuItem(
                      value: kCustomAvatarSpec.id,
                      child: const Text('Custom GLB')),
              ],
              onChanged: (v) {
                if (v != null) _selectSpec(kind, v);
              },
            ),
            const SizedBox(height: 12),
          ],
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
