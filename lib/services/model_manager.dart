import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/model_catalog.dart';

/// Tracks where downloaded models live and which spec is selected per kind.
///
/// Layout:
///   `appDocs/models/<kind>/<specId>/`   (extracted archive or single file)
///   `appDocs/models/selection.json`     `{"llm": id, "stt": id, ...}`
class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  Directory? _root;

  Future<Directory> get root async {
    _root ??= Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'models'),
    );
    return _root!;
  }

  Future<Directory> dirFor(ModelSpec spec) async =>
      Directory(p.join((await root).path, spec.kind.name, spec.id));

  Future<File> _selectionFile() async =>
      File(p.join((await root).path, 'selection.json'));

  Future<Map<ModelKind, String>> selection() async {
    final f = await _selectionFile();
    if (!await f.exists()) return {};
    try {
      final raw =
          jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return {
        for (final kind in ModelKind.values)
          if (raw[kind.name] is String) kind: raw[kind.name] as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> select(ModelKind kind, String specId) async {
    final sel = await selection();
    sel[kind] = specId;
    final f = await _selectionFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({for (final k in sel.keys) k.name: sel[k]}));
  }

  Future<ModelSpec?> selectedSpec(ModelKind kind) async {
    final sel = await selection();
    final id = sel[kind];
    if (id == null) return null;
    return specById(kind, id);
  }

  /// Directory containing a spec's installed payload, or null if not
  /// downloaded yet. For file-based specs returns the file itself.
  Future<Directory?> installDir(ModelSpec spec) async {
    final dir = await dirFor(spec);
    final marker = File(p.join(dir.path, '.installed'));
    if (await dir.exists() && await marker.exists()) return dir;
    return null;
  }

  Future<bool> isInstalled(ModelSpec spec) async =>
      (await installDir(spec)) != null;

  /// Path to the primary payload file for non-archive specs.
  Future<File> payloadFile(ModelSpec spec) async =>
      File(p.join((await dirFor(spec)).path, spec.fileName));

  /// The currently selected + installed spec for [kind], or null.
  Future<ModelSpec?> activeSpec(ModelKind kind) async {
    final sel = await selection();
    final id = sel[kind];
    if (id == null) return null;
    // Custom avatar: file was imported, not downloaded.
    if (kind == ModelKind.avatar && id == kCustomAvatarSpec.id) {
      final f = await payloadFile(kCustomAvatarSpec);
      return (await f.exists()) ? kCustomAvatarSpec : null;
    }
    final spec = specById(kind, id);
    return (await isInstalled(spec)) ? spec : null;
  }

  /// Imports a .glb file as the active avatar.
  Future<void> installCustomAvatar(String sourcePath) async {
    final dest = await payloadFile(kCustomAvatarSpec);
    await dest.parent.create(recursive: true);
    await File(sourcePath).copy(dest.path);
    await select(ModelKind.avatar, kCustomAvatarSpec.id);
  }

  Future<bool> get allInstalled async {
    for (final kind in ModelKind.values) {
      if (await activeSpec(kind) == null) return false;
    }
    return true;
  }

  Future<void> delete(ModelSpec spec) async {
    final dir = await dirFor(spec);
    if (await dir.exists()) await dir.delete(recursive: true);
    final sel = await selection();
    if (sel[spec.kind] == spec.id) {
      sel.remove(spec.kind);
      final f = await _selectionFile();
      await f.writeAsString(
        jsonEncode({for (final k in sel.keys) k.name: sel[k]}),
      );
    }
  }

  Future<int> directorySize(Directory dir) async {
    var total = 0;
    if (!await dir.exists()) return 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// Finds the first file under [dir] whose name matches [pattern]
  /// (regex on the file name, case-insensitive).
  Future<File?> findFile(Directory dir, String pattern) async {
    final re = RegExp(pattern, caseSensitive: false);
    if (!await dir.exists()) return null;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File && re.hasMatch(p.basename(e.path))) return e;
    }
    return null;
  }

  Future<Directory?> findDir(Directory dir, String pattern) async {
    final re = RegExp(pattern, caseSensitive: false);
    if (!await dir.exists()) return null;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is Directory && re.hasMatch(p.basename(e.path))) return e;
    }
    return null;
  }
}
