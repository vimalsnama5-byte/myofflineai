import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// Drives the GLB avatar inside a [ViewerWidget]: loads the model,
/// discovers morph targets for lip sync + blinking, and plays an idle
/// skeletal animation when the model ships one.
class AvatarController {
  ThermionViewer? _viewer;
  ThermionAsset? _asset;

  /// child entity -> (all morph names, index of mouth target, L/R blink idx)
  final Map<ThermionEntity, _MorphInfo> _morphEntities = {};

  List<double> _envelope = const [];
  int _envIndex = 0;
  Timer? _lipTimer;
  Timer? _blinkTimer;
  final _rng = Random();
  bool _speaking = false;

  bool get hasAvatar => _asset != null;

  Future<void> attach(ThermionViewer viewer, String glbPath) async {
    _viewer = viewer;
    final bytes = await File(glbPath).readAsBytes();
    _asset = await viewer.loadGltfFromBuffer(bytes);
    await _frameCamera();
    try {
      await _scanMorphs();
    } catch (_) {
      // No usable morph targets — avatar still renders, just no lip sync.
    }
    try {
      await _startIdleAnimation();
    } catch (_) {}
    _startBlinkLoop();
  }

  /// Positions the camera to fit the model's real bounding box — reliable
  /// regardless of glTF units or whether the root transform affects
  /// skinned vertices.
  Future<void> _frameCamera() async {
    final asset = _asset;
    final viewer = _viewer;
    if (asset == null || viewer == null) return;
    final box = await asset.getBoundingBox();
    final size = vm.Vector3(
      box.max.x - box.min.x,
      box.max.y - box.min.y,
      box.max.z - box.min.z,
    );
    final center = vm.Vector3(
      (box.min.x + box.max.x) / 2,
      (box.min.y + box.max.y) / 2,
      (box.min.z + box.max.z) / 2,
    );
    final extent = max(size.x, max(size.y, size.z)).clamp(0.01, 1e6);
    final camera = await viewer.getActiveCamera();
    await camera.lookAt(
      center + vm.Vector3(0, extent * 0.1, extent * 1.6),
      focus: center,
    );
  }

  Future<void> _scanMorphs() async {
    final asset = _asset;
    if (asset == null) return;
    _morphEntities.clear();
    final children = await asset.getChildEntities();
    for (final entity in children) {
      final names = await asset.getMorphTargetNames(entity: entity);
      if (names.isEmpty) continue;
      final lower = names.map((n) => n.toLowerCase()).toList();
      final mouthIdx = lower.indexWhere((n) =>
          n == 'jawopen' ||
          n == 'mouthopen' ||
          n == 'viseme_aa' ||
          n.contains('surprised'));
      final blinkL = lower.indexWhere((n) => n.contains('blink') && n.contains('l'));
      final blinkR = lower.indexWhere((n) => n.contains('blink') && n.contains('r'));
      final smile = lower.indexWhere((n) => n.contains('smile'));
      if (mouthIdx >= 0 || blinkL >= 0) {
        _morphEntities[entity] = _MorphInfo(
          count: names.length,
          mouth: mouthIdx,
          blinkL: blinkL,
          blinkR: blinkR,
          smile: smile,
        );
      }
    }
  }

  Future<void> _startIdleAnimation() async {
    final asset = _asset;
    if (asset == null) return;
    final names = await asset.getGltfAnimationNames();
    if (names.isEmpty) return;
    const prefs = ['idle', 'standing', 'breathing', 'wait'];
    String? pick;
    for (final p in prefs) {
      pick = names.cast<String?>().firstWhere(
            (n) => n!.toLowerCase().contains(p),
            orElse: () => null,
          );
      if (pick != null) break;
    }
    pick ??= names.first;
    await asset.playGltfAnimationByName(pick, loop: true, crossfade: 0.3);
  }

  void _startBlinkLoop() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(
      Duration(milliseconds: 2200 + _rng.nextInt(2600)),
      (_) => _blink(),
    );
  }

  Future<void> _blink() async {
    for (final entry in _morphEntities.entries) {
      final info = entry.value;
      if (info.blinkL < 0 && info.blinkR < 0) continue;
      final weights = List<double>.filled(info.count, 0);
      if (info.blinkL >= 0) weights[info.blinkL] = 1;
      if (info.blinkR >= 0) weights[info.blinkR] = 1;
      await _asset?.setMorphTargetWeights(entry.key, weights);
    }
    await Future.delayed(const Duration(milliseconds: 120));
    if (_speaking) return; // lip timer owns the mouth array
    await _applyWeights(mouthOpen: _mouthValue());
  }

  double _mouthValue() =>
      _speaking && _envIndex < _envelope.length ? _envelope[_envIndex] : 0.0;

  Future<void> _applyWeights({required double mouthOpen}) async {
    for (final entry in _morphEntities.entries) {
      final info = entry.value;
      final weights = List<double>.filled(info.count, 0);
      if (info.mouth >= 0) weights[info.mouth] = mouthOpen;
      if (info.smile >= 0) weights[info.smile] = 0.25;
      await _asset?.setMorphTargetWeights(entry.key, weights);
    }
  }

  /// Start lip-syncing to a playback envelope (values 0..1 per ~50 ms tick).
  void startSpeaking(List<double> envelope) {
    if (_morphEntities.isEmpty) return;
    _speaking = true;
    _envelope = envelope;
    _envIndex = 0;
    _lipTimer?.cancel();
    _lipTimer = Timer.periodic(const Duration(milliseconds: 50), (t) async {
      if (_envIndex >= _envelope.length) {
        await stopSpeaking();
        return;
      }
      // Shape the curve so quiet speech still reads as mouth movement.
      final v = _envelope[_envIndex++];
      await _applyWeights(mouthOpen: pow(v, 0.6).clamp(0.0, 1.0).toDouble());
    });
  }

  Future<void> stopSpeaking() async {
    _speaking = false;
    _lipTimer?.cancel();
    _lipTimer = null;
    await _applyWeights(mouthOpen: 0.0);
  }

  /// Small "listening" cue — nod via a subtle smile weight bump.
  Future<void> poke() async {
    if (_speaking) return;
    await _applyWeights(mouthOpen: 0.15);
    await Future.delayed(const Duration(milliseconds: 180));
    if (!_speaking) await _applyWeights(mouthOpen: 0.0);
  }

  static vm.Vector3 cameraPosition() => vm.Vector3(0, 0, 1.9);

  Future<void> dispose() async {
    _lipTimer?.cancel();
    _blinkTimer?.cancel();
    final asset = _asset;
    _asset = null;
    _morphEntities.clear();
    if (asset != null) await _viewer?.destroyAsset(asset);
    _viewer = null;
  }
}

class _MorphInfo {
  final int count;
  final int mouth;
  final int blinkL;
  final int blinkR;
  final int smile;
  const _MorphInfo({
    required this.count,
    required this.mouth,
    required this.blinkL,
    required this.blinkR,
    required this.smile,
  });
}
