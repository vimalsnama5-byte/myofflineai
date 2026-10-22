import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_manager.dart';

/// Offline speech-to-text over sherpa-onnx Whisper + `record` mic capture.
///
/// Push-to-talk flow: [startListening] opens the mic stream and feeds
/// samples into an [sherpa.OfflineStream]; [stopAndTranscribe] decodes.
/// A lightweight energy VAD auto-finishes after ~1.4 s of trailing silence.
class SttService {
  sherpa.OfflineRecognizer? _recognizer;
  sherpa.OfflineStream? _stream;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;
  final _pending = <Float32List>[];

  // Silence detection state.
  double _noiseFloor = 0.008;
  double _silenceMs = 0;
  bool _heardSpeech = false;
  void Function()? onSilenceTimeout;
  void Function(double level)? onLevel;

  bool get isListening => _micSub != null;

  static const _silenceLimitMs = 1400;
  static const _sampleRate = 16000;

  /// [language] is an ISO code like 'en' or 'ta' for multilingual Whisper;
  /// empty string lets Whisper auto-detect. Ignored by .en models.
  Future<void> loadModel(Directory modelDir, {String language = 'en'}) async {
    final encoder = await ModelManager.instance
        .findFile(modelDir, r'encoder.*\.onnx$');
    final decoder = await ModelManager.instance
        .findFile(modelDir, r'decoder.*\.onnx$');
    final tokens = await ModelManager.instance
        .findFile(modelDir, r'tokens\.txt$');
    if (encoder == null || decoder == null || tokens == null) {
      throw StateError('STT model files missing in ${modelDir.path}');
    }
    _recognizer?.free();
    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: encoder.path,
            decoder: decoder.path,
            language: language,
          ),
          tokens: tokens.path,
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
      ),
    );
  }

  Future<bool> startListening() async {
    final recognizer = _recognizer;
    if (recognizer == null) throw StateError('STT model not loaded');
    _recorder ??= AudioRecorder();
    if (!await _recorder!.hasPermission()) return false;

    _stream?.free();
    _stream = recognizer.createStream();
    _pending.clear();
    _silenceMs = 0;
    _heardSpeech = false;

    final audioStream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _micSub = audioStream.listen(_onMicData);
    return true;
  }

  void _onMicData(Uint8List chunk) {
    final samples = _pcm16ToFloat(chunk);
    _pending.add(samples);
    _stream?.acceptWaveform(samples: samples, sampleRate: _sampleRate);

    // RMS of this chunk for VAD + mic level UI.
    var sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    final rms = samples.isEmpty ? 0.0 : (sum / samples.length);
    onLevel?.call(rms.clamp(0.0, 0.4) * 2.5);

    final ms = chunk.length / 2 / _sampleRate * 1000;
    if (rms > _noiseFloor * 2.5) {
      _heardSpeech = true;
      _silenceMs = 0;
    } else if (_heardSpeech) {
      _silenceMs += ms;
      if (_silenceMs > _silenceLimitMs) {
        _silenceMs = 0;
        _heardSpeech = false;
        onSilenceTimeout?.call();
      }
    } else {
      // Adapt the noise floor slowly while no speech is present.
      _noiseFloor = _noiseFloor * 0.98 + rms * 0.02;
    }
  }

  Future<String> stopAndTranscribe() async {
    await _micSub?.cancel();
    _micSub = null;
    await _recorder?.stop();
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return '';
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text.trim();
    stream.free();
    _stream = null;
    _pending.clear();
    return text;
  }

  Future<void> cancel() async {
    await _micSub?.cancel();
    _micSub = null;
    await _recorder?.stop();
    _stream?.free();
    _stream = null;
    _pending.clear();
  }

  Future<void> dispose() async {
    await cancel();
    _recognizer?.free();
    _recognizer = null;
    await _recorder?.dispose();
    _recorder = null;
  }

  static Float32List _pcm16ToFloat(Uint8List bytes) {
    final n = bytes.lengthInBytes ~/ 2;
    final out = Float32List(n);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}
