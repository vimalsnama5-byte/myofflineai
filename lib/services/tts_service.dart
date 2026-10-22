import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_manager.dart';

/// Result of a TTS synthesis: playable WAV plus the raw PCM used to
/// drive avatar lip-sync envelopes.
class SpeechResult {
  final String wavPath;
  final Float32List samples;
  final int sampleRate;
  final Duration duration;
  const SpeechResult({
    required this.wavPath,
    required this.samples,
    required this.sampleRate,
    required this.duration,
  });
}

/// Offline text-to-speech via sherpa-onnx VITS (Piper voice), played back
/// through audioplayers from a generated WAV file.
class TtsService {
  sherpa.OfflineTts? _tts;
  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;
  Stream<void> get onComplete => _player.onPlayerComplete;

  Future<void> loadModel(Directory modelDir) async {
    final model =
        await ModelManager.instance.findFile(modelDir, r'\.onnx$');
    final tokens =
        await ModelManager.instance.findFile(modelDir, r'tokens\.txt$');
    final dataDir =
        await ModelManager.instance.findDir(modelDir, r'espeak');
    if (model == null || tokens == null) {
      throw StateError('TTS model files missing in ${modelDir.path}');
    }
    _tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: model.path,
            tokens: tokens.path,
            dataDir: dataDir?.path ?? '',
          ),
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
      ),
    );
  }

  bool get isLoaded => _tts != null;

  /// Synthesizes [text] to a WAV file on disk. Returns null for empty text.
  Future<SpeechResult?> synthesize(String text) async {
    final tts = _tts;
    final trimmed = text.trim();
    if (tts == null || trimmed.isEmpty) return null;
    final audio = tts.generate(text: trimmed, sid: 0, speed: 1.0);
    if (audio.sampleRate <= 0 || audio.samples.isEmpty) return null;

    final tmp = await getTemporaryDirectory();
    final wavPath = p.join(tmp.path, 'packet_tts.wav');
    sherpa.writeWave(
      filename: wavPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    return SpeechResult(
      wavPath: wavPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
      duration: Duration(
        microseconds:
            (audio.samples.length / audio.sampleRate * 1e6).round(),
      ),
    );
  }

  /// Per-[windowMs] RMS envelope of [samples], normalized 0..1.
  /// Used to drive mouth morph weights in sync with playback.
  List<double> amplitudeEnvelope(Float32List samples, int sampleRate,
      {int windowMs = 50}) {
    final window = max(1, sampleRate * windowMs ~/ 1000);
    final out = <double>[];
    var peak = 1e-6;
    for (var i = 0; i < samples.length; i += window) {
      var sum = 0.0;
      final end = min(i + window, samples.length);
      for (var j = i; j < end; j++) {
        sum += samples[j] * samples[j];
      }
      final rms = sqrt(sum / (end - i));
      if (rms > peak) peak = rms;
      out.add(rms);
    }
    return out.map((v) => (v / peak).clamp(0.0, 1.0)).toList();
  }

  Future<void> play(SpeechResult result) =>
      _player.play(DeviceFileSource(result.wavPath));

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await _player.dispose();
  }
}
