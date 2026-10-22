import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/model_catalog.dart';
import '../services/download_service.dart';
import '../services/model_manager.dart';
import 'home_screen.dart';

/// First-run screen: pick one spec per model kind and download it.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _download = DownloadService();
  final Map<String, double> _progress = {};
  final Map<String, String> _status = {};
  final Map<String, bool> _installed = {};
  final Map<ModelKind, String> _picked = {};
  StreamSubscription? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final sel = await ModelManager.instance.selection();
    for (final kind in ModelKind.values) {
      _picked[kind] = sel[kind] ?? specsFor(kind).first.id;
      for (final spec in specsFor(kind)) {
        _installed[spec.id] = await ModelManager.instance.isInstalled(spec);
      }
    }
    if (mounted) setState(() {});
  }

  bool get _allReady =>
      ModelKind.values.every((k) => _installed[_picked[k]] == true);

  Future<void> _startDownload(ModelSpec spec) async {
    setState(() {
      _busy = true;
      _status[spec.id] = 'Starting…';
    });
    _sub = _download.download(spec).listen(
      (p) {
        setState(() {
          _progress[spec.id] = p.fraction;
          _status[spec.id] = p.status;
        });
      },
      onError: (e) {
        setState(() {
          _busy = false;
          _status[spec.id] = 'Failed: $e';
        });
      },
      onDone: () async {
        await _refresh();
        setState(() {
          _busy = false;
          _picked[spec.kind] = spec.id;
        });
      },
    );
  }

  Future<void> _pickCustomGlb() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['glb'],
    );
    if (result.isEmpty) return;
    final path = result.single.path;
    if (path == null) return;
    await ModelManager.instance.installCustomAvatar(path);
    await _refresh();
    setState(() => _picked[ModelKind.avatar] = kCustomAvatarSpec.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Packet AI — one-time setup')),
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'Everything runs offline. Download one model for each part — '
            'this only needs internet once.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          _kindSection(
            'AI brain (GGUF, llama.cpp)',
            ModelKind.llm,
          ),
          _kindSection('Ears (Whisper STT)', ModelKind.stt),
          _kindSection('Voice (Piper TTS)', ModelKind.tts),
          _kindSection('Avatar (3D model)', ModelKind.avatar,
              trailing: TextButton.icon(
                onPressed: _busy ? null : _pickCustomGlb,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import .glb'),
              )),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _allReady && !_busy
                ? () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomeScreen()))
                : null,
            icon: const Icon(Icons.rocket_launch),
            label: Text(_allReady ? 'Launch Packet AI' : 'Download all models to continue'),
          ),
        ],
        ),
      ),
    );
  }

  Widget _kindSection(String title, ModelKind kind, {Widget? trailing}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 4),
            RadioGroup<String>(
              groupValue: _picked[kind],
              onChanged: (v) {
                if (v != null && !_busy) {
                  setState(() => _picked[kind] = v);
                }
              },
              child: Column(
                children: specsFor(kind).map((spec) => _specTile(spec)).toList(),
              ),
            ),
            if (kind == ModelKind.avatar &&
                _picked[kind] == kCustomAvatarSpec.id)
              ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Custom GLB'),
                subtitle: const Text('Imported file selected'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _specTile(ModelSpec spec) {
    final installed = _installed[spec.id] == true;
    final progress = _progress[spec.id];
    final status = _status[spec.id];
    final picked = _picked[spec.kind] == spec.id;

    return Column(
      children: [
        RadioListTile<String>(
          dense: true,
          value: spec.id,
          title: Text(spec.name),
          subtitle: Text('${spec.description}  •  ${spec.sizeLabel}'),
          secondary: installed
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null,
        ),
        if (picked && !installed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (progress != null)
                  LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(status ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54)),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _startDownload(spec),
                      child: Text(_installed[spec.id] == true
                          ? 'Installed'
                          : 'Download'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _download.dispose();
    super.dispose();
  }
}
