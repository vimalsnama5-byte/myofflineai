import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../services/assistant_controller.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = AssistantController();
  final _scroll = ScrollController();
  bool _avatarRequested = false;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.init());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Packet AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(controller: _controller),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          _scrollToBottom();
          return Column(
            children: [
              Expanded(flex: 5, child: _avatarArea()),
              _statusBar(),
              Expanded(flex: 4, child: _transcript()),
            ],
          );
        },
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _micButton(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _avatarArea() {
    final err = _controller.error;
    if (_controller.state == AssistantState.error && err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(err, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const SetupScreen())),
                child: const Text('Open setup'),
              ),
            ],
          ),
        ),
      );
    }
    final avatarErr = _controller.avatarError;
    return Stack(
      children: [
        _AvatarView(
          onViewerAvailable: (viewer) async {
            if (_avatarRequested) return;
            _avatarRequested = true;
            final path = await _controller.avatarGlbPath();
            if (path != null) {
              await _controller.attachAvatar(viewer, path);
            }
          },
        ),
        if (avatarErr != null)
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text('Avatar error:\n$avatarErr',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          ),
      ],
    );
  }

  Widget _statusBar() {
    final c = _controller;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          _stateIcon(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.status, overflow: TextOverflow.ellipsis),
                if (c.error != null)
                  Text(c.error!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11)),
              ],
            ),
          ),
          if (c.state == AssistantState.listening)
            SizedBox(
              width: 80,
              child: LinearProgressIndicator(
                value: c.micLevel.clamp(0.0, 1.0),
                minHeight: 4,
              ),
            ),
        ],
      ),
    );
  }

  Widget _stateIcon() {
    switch (_controller.state) {
      case AssistantState.listening:
        return const Icon(Icons.mic, color: Colors.redAccent, size: 18);
      case AssistantState.thinking:
        return const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2));
      case AssistantState.speaking:
        return const Icon(Icons.volume_up, color: Colors.lightGreen, size: 18);
      case AssistantState.ready:
        return const Icon(Icons.check_circle_outline,
            color: Colors.lightGreen, size: 18);
      default:
        return const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2));
    }
  }

  Widget _transcript() {
    final items = _controller.transcript;
    if (items.isEmpty) {
      return const Center(
        child: Text('Tap the mic and talk to me.',
            style: TextStyle(color: Colors.white38)),
      );
    }
    final partial = _controller.partialReply;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: items.length + (partial != null ? 1 : 0),
      itemBuilder: (context, i) {
        final m = i < items.length
            ? items[i]
            : TranscriptEntry('assistant', partial!);
        final isUser = m.role == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              color: isUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(m.text),
          ),
        );
      },
    );
  }

  Widget _micButton() {
    final c = _controller;
    final busy = c.state == AssistantState.initializing ||
        c.state == AssistantState.thinking;
    final listening = c.state == AssistantState.listening;
    return FloatingActionButton.large(
      onPressed: busy ? null : () => unawaited(c.toggleMic()),
      backgroundColor: listening
          ? Colors.redAccent
          : Theme.of(context).colorScheme.primary,
      child: Icon(
        listening
            ? Icons.stop
            : (c.state == AssistantState.speaking
                ? Icons.stop
                : Icons.mic),
        size: 36,
      ),
    );
  }
}

/// Wraps thermion's ViewerWidget with our avatar-attach callback.
class _AvatarView extends StatelessWidget {
  final Future<void> Function(ThermionViewer viewer) onViewerAvailable;
  const _AvatarView({required this.onViewerAvailable});

  @override
  Widget build(BuildContext context) {
    return ViewerWidget(
      initialCameraPosition: vm.Vector3(0, 0, 1.9),
      background: const Color(0xFF101018),
      manipulatorType: ManipulatorType.ORBIT,
      directLight: DirectLight.sun(
        intensity: 80000,
        direction: vm.Vector3(-0.4, -0.8, -0.6),
        castShadows: false,
      ),
      onViewerAvailable: onViewerAvailable,
      initial: const Center(child: CircularProgressIndicator()),
    );
  }
}
