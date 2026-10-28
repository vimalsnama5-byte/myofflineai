import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:thermion_flutter/thermion_flutter.dart' show ThermionViewer;

import '../models/model_catalog.dart';
import 'avatar_controller.dart';
import 'llm_service.dart';
import 'memory_service.dart';
import 'model_manager.dart';
import 'stt_service.dart';
import 'tts_service.dart';

enum AssistantState { initializing, ready, listening, thinking, speaking, error }

class TranscriptEntry {
  final String role;
  final String text;
  const TranscriptEntry(this.role, this.text);
}

/// Coordinates the full voice loop:
/// mic → whisper STT → llama.cpp reply → piper TTS → avatar lip sync.
class AssistantController extends ChangeNotifier {
  final stt = SttService();
  final llm = LlmService();
  final tts = TtsService();
  final avatar = AvatarController();

  AssistantState state = AssistantState.initializing;
  String status = 'Starting up…';
  String? error;
  String? avatarError;
  String? partialReply;
  final transcript = <TranscriptEntry>[];
  final logs = <String>[];
  double micLevel = 0;

  StreamSubscription<void>? _playbackSub;
  File? _logFile;

  /// Completes when init() finishes (success or error) — the avatar waits
  /// on this so heavy native work never runs concurrently with model loads.
  final initDone = Completer<void>();

  void log(String message) {
    final line =
        '${DateTime.now().toIso8601String().substring(11, 19)}  $message';
    logs.add(line);
    if (logs.length > 200) logs.removeAt(0);
    unawaited(_logFile?.writeAsString('$line\n', mode: FileMode.append));
  }

  void _fail(String phase, Object e, {AssistantState next = AssistantState.ready}) {
    log('$phase failed: $e');
    error = '$phase: $e';
    status = 'Error — $phase';
    state = next;
    notifyListeners();
  }

  Future<void> init() async {
    try {
      await MemoryService.instance.init();
      _language = await MemoryService.instance.getPref('language') ?? 'en';
      await _restoreTranscript();
      final docs = await getApplicationDocumentsDirectory();
      _logFile = File('${docs.path}/packet_ai.log');
      await File('${docs.path}/.init_in_progress').create(recursive: true);
      log('init() started');

      for (final kind in ModelKind.values) {
        final spec = await ModelManager.instance.activeSpec(kind);
        if (spec == null) {
          state = AssistantState.error;
          error = 'Missing ${kind.name} model — open setup.';
          notifyListeners();
          return;
        }
      }

      status = 'Loading speech model…';
      notifyListeners();
      await _loadStt();

      status = 'Loading voice…';
      notifyListeners();
      await _loadTts();

      status = 'Loading AI brain… (may take a moment)';
      notifyListeners();
      await _loadLlm();

      status = 'Ready — tap the mic';
      state = AssistantState.ready;
      error = null;
      notifyListeners();
      try {
        final docs = await getApplicationDocumentsDirectory();
        await File('${docs.path}/.init_in_progress').delete();
        log('init() complete');
      } catch (_) {}
    } catch (e) {
      _fail('Startup', e, next: AssistantState.error);
    } finally {
      if (!initDone.isCompleted) initDone.complete();
    }
  }

  Future<Directory> _installDirFor(ModelKind kind) async =>
      (await ModelManager.instance
          .installDir((await ModelManager.instance.selectedSpec(kind))!))!;

  Future<void> _loadStt() async {
    log('Loading STT');
    stt.onSilenceTimeout = () {
      if (state == AssistantState.listening) {
        unawaited(finishListening());
      }
    };
    stt.onLevel = (level) {
      micLevel = level;
      notifyListeners();
    };
    await stt.loadModel(await _installDirFor(ModelKind.stt),
        language: _language);
    log('STT ready (lang=$_language)');
  }

  String _language = 'en';
  String get language => _language;

  Future<void> _loadTts() async {
    log('Loading TTS');
    await tts.loadModel(await _installDirFor(ModelKind.tts));
    log('TTS ready');
  }

  Future<void> _loadLlm() async {
    log('Loading LLM');
    final spec = (await ModelManager.instance.selectedSpec(ModelKind.llm))!;
    await llm.loadModel(
        await _installDirFor(ModelKind.llm), spec.fileName,
        language: _language);
    final history = await MemoryService.instance.recentMessages(limit: 12);
    llm.seedHistory(
        history.map((m) => (m.role, m.text)).toList());
    log('LLM ready (${history.length} history messages)');
  }

  /// Called by the UI once the thermion viewer exists.
  Future<void> attachAvatar(ThermionViewer viewer, String glbPath) async {
    try {
      await avatar.attach(viewer, glbPath);
      avatarError = null;
      log('Avatar attached');
    } catch (e) {
      avatarError = e.toString();
      log('Avatar attach failed: $e');
      notifyListeners();
    }
  }

  Future<void> _restoreTranscript() async {
    final history = await MemoryService.instance.recentMessages();
    transcript
      ..clear()
      ..addAll(history.map((m) => TranscriptEntry(m.role, m.text)));
  }

  /// Toggle listening on/off.
  Future<void> toggleMic() async {
    if (state == AssistantState.listening) {
      await finishListening();
    } else if (state == AssistantState.ready ||
        state == AssistantState.error) {
      await startListening();
    } else if (state == AssistantState.speaking) {
      await interrupt();
    }
  }

  Future<void> startListening() async {
    error = null;
    bool ok;
    try {
      ok = await stt.startListening();
    } catch (e) {
      _fail('Microphone', e);
      return;
    }
    if (!ok) {
      state = AssistantState.ready;
      status = 'Microphone permission denied';
      notifyListeners();
      return;
    }
    state = AssistantState.listening;
    status = 'Listening…';
    notifyListeners();
    unawaited(avatar.poke());
  }

  /// Stop the mic, transcribe, and run the assistant turn.
  Future<void> finishListening() async {
    if (state != AssistantState.listening) return;
    state = AssistantState.thinking;
    status = 'Transcribing…';
    notifyListeners();

    String text;
    try {
      text = await stt.stopAndTranscribe();
    } catch (e) {
      _fail('Transcribe', e);
      return;
    }
    if (text.isEmpty) {
      state = AssistantState.ready;
      status = "Didn't catch that — tap the mic and try again";
      notifyListeners();
      return;
    }
    await _runTurn(text);
  }

  Future<void> interrupt() async {
    await tts.stop();
    await avatar.stopSpeaking();
    await stt.cancel();
    state = AssistantState.ready;
    status = 'Ready — tap the mic';
    notifyListeners();
  }

  Future<void> _runTurn(String userText) async {
    transcript.add(TranscriptEntry('user', userText));
    await MemoryService.instance.addMessage('user', userText);
    status = 'Thinking…';
    notifyListeners();

    String reply;
    try {
      final buf = StringBuffer();
      partialReply = '';
      await for (final delta in llm.respond(userText)) {
        buf.write(delta);
        partialReply = buf.toString();
        notifyListeners();
      }
      reply = buf.toString().trim();
    } catch (e) {
      _fail('Brain', e);
      partialReply = null;
      return;
    } finally {
      partialReply = null;
    }
    if (reply.isEmpty) reply = "I'm not sure what to say.";
    transcript.add(TranscriptEntry('assistant', reply));
    await MemoryService.instance.addMessage('assistant', reply);

    status = 'Synthesizing voice…';
    state = AssistantState.speaking;
    notifyListeners();

    SpeechResult? speech;
    try {
      speech = await tts.synthesize(reply);
    } catch (e) {
      _fail('Voice', e);
      return;
    }
    if (speech == null) {
      state = AssistantState.ready;
      status = 'Ready — tap the mic';
      notifyListeners();
      return;
    }

    final envelope = tts.amplitudeEnvelope(speech.samples, speech.sampleRate);
    avatar.startSpeaking(envelope);
    await tts.play(speech);

    await _playbackSub?.cancel();
    _playbackSub = tts.onComplete.listen((_) async {
      await avatar.stopSpeaking();
      state = AssistantState.ready;
      status = 'Ready — tap the mic';
      notifyListeners();
    });
    // Fallback in case onComplete never fires.
    unawaited(Future.delayed(speech.duration + const Duration(seconds: 2),
        () async {
      if (state == AssistantState.speaking) {
        await avatar.stopSpeaking();
        state = AssistantState.ready;
        status = 'Ready — tap the mic';
        notifyListeners();
      }
    }));
  }

  /// Switch assistant language ('en' or 'ta'). Rebuilds the recognizer
  /// and the LLM system prompt; takes effect immediately.
  Future<void> setLanguage(String code) async {
    if (code == _language) return;
    _language = code;
    await MemoryService.instance.setPref('language', code);
    log('Language -> $code');
    llm.updateLanguage(code);
    if (stt.isListening) await stt.cancel();
    try {
      await stt.loadModel(await _installDirFor(ModelKind.stt),
          language: code);
    } catch (e) {
      log('STT reload failed: $e');
    }
    notifyListeners();
  }

  Future<void> clearMemory() async {
    await MemoryService.instance.clearHistory();
    llm.clearHistory();
    transcript.clear();
    notifyListeners();
  }

  /// Path of the currently selected avatar GLB.
  Future<String?> avatarGlbPath() async {
    final spec = await ModelManager.instance.activeSpec(ModelKind.avatar);
    if (spec == null) return null;
    final f = await ModelManager.instance.payloadFile(spec);
    return f.path;
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    unawaited(stt.dispose());
    unawaited(llm.unload());
    unawaited(tts.dispose());
    unawaited(avatar.dispose());
    super.dispose();
  }
}
