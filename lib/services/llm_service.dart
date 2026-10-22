import 'dart:io';

import 'package:llamadart/llamadart.dart';

/// llama.cpp-backed offline chat brain via llamadart.
///
/// Wraps [LlamaEngine] (GGUF file load) and a [ChatSession] that keeps
/// multi-turn history with the model's own chat template.
class LlmService {
  LlamaEngine? _engine;
  ChatSession? _session;

  bool get isLoaded => _engine != null && _session != null;

  static const _systemPrompt =
      'You are Packet, a friendly on-device voice assistant. '
      'Reply in one or two short spoken sentences. No markdown, no emoji, '
      'no lists — plain conversational text only.';

  Future<void> loadModel(Directory modelDir, String fileName) async {
    final gguf = File('${modelDir.path}${Platform.pathSeparator}$fileName');
    if (!await gguf.exists()) {
      throw StateError('GGUF model not found: ${gguf.path}');
    }
    await unload();
    _engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(gguf.path)),
      params: const ModelParams(
        contextSize: 2048,
        device: ComputeDevice.cpu,
        numberOfThreads: 4,
        useMmap: true,
      ),
    );
    _session = ChatSession(_engine!, systemPrompt: _systemPrompt);
  }

  /// Restore persisted history into the session (roles user/assistant only).
  void seedHistory(List<(String, String)> messages) {
    final session = _session;
    if (session == null) return;
    session.reset(keepSystemPrompt: true);
    for (final (role, text) in messages) {
      session.addMessage(
        LlamaChatMessage.fromText(
          role: role == 'user' ? LlamaChatRole.user : LlamaChatRole.assistant,
          text: text,
        ),
      );
    }
  }

  void clearHistory() => _session?.reset(keepSystemPrompt: true);

  /// Streams the reply as text deltas.
  Stream<String> respond(String userText) async* {
    final session = _session;
    if (session == null) throw StateError('LLM not loaded');
    await for (final chunk in session.create([LlamaTextContent(userText)])) {
      final delta = chunk.text;
      if (delta.isNotEmpty) yield delta;
    }
  }

  /// Non-streaming convenience.
  Future<String> complete(String userText) async {
    final buf = StringBuffer();
    await for (final d in respond(userText)) {
      buf.write(d);
    }
    return buf.toString();
  }

  Future<void> unload() async {
    _session = null;
    final engine = _engine;
    _engine = null;
    await engine?.unloadModel();
  }
}
