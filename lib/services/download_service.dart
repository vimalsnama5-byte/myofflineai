import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/model_catalog.dart';
import 'model_manager.dart';

/// Streams a download's lifecycle to the UI.
class DownloadProgress {
  final double fraction; // 0..1 overall
  final String status;
  final int receivedBytes;
  const DownloadProgress(this.fraction, this.status,
      [this.receivedBytes = 0]);
}

/// Downloads [ModelSpec] file lists (plus optional HuggingFace repo-prefix
/// pulls) directly to disk. No archive extraction — keeps memory flat.
class DownloadService {
  final _client = http.Client();

  /// Downloads every file in [spec] into its install dir.
  /// Wipes any partial install first so a killed run can resume cleanly.
  /// `spec.files` download sequentially with byte progress; HF-prefix files
  /// (many small ones) batch 6 at a time with count progress.
  Stream<DownloadProgress> download(ModelSpec spec) async* {
    yield const DownloadProgress(0.0, 'Resolving file list…');
    final smallFiles = await _resolveSmallFiles(spec);

    final dir = await ModelManager.instance.dirFor(spec);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final total = spec.files.length + smallFiles.length;
    var done = 0;

    // Explicit files: sequential, with real byte-level progress.
    for (final f in spec.files) {
      final dest = File(p.join(dir.path, f.relPath));
      await dest.parent.create(recursive: true);
      await for (final pr in _streamToFile(f.url, dest)) {
        yield DownloadProgress(
          (done + pr.fraction) / total,
          '${p.basename(f.relPath)} — ${_mb(pr.receivedBytes)} MB',
          pr.receivedBytes,
        );
      }
      done++;
      yield DownloadProgress(done / total, 'Files $done/$total');
    }

    // Small repo-prefix files: parallel batches with count progress.
    const batchSize = 6;
    for (var i = 0; i < smallFiles.length; i += batchSize) {
      final batch = smallFiles.sublist(
        i,
        i + batchSize > smallFiles.length ? smallFiles.length : i + batchSize,
      );
      await Future.wait(batch.map((f) async {
        final dest = File(p.join(dir.path, f.relPath));
        await dest.parent.create(recursive: true);
        await for (final _ in _streamToFile(f.url, dest)) {}
      }));
      done += batch.length;
      yield DownloadProgress(
        done / total,
        'Extra files $done/$total',
      );
    }

    await File(p.join(dir.path, '.installed')).writeAsString(
      DateTime.now().toIso8601String(),
    );
    await ModelManager.instance.select(spec.kind, spec.id);
    yield const DownloadProgress(1.0, 'Installed');
  }

  Future<List<ModelFileItem>> _resolveSmallFiles(ModelSpec spec) async {
    final files = <ModelFileItem>[];
    if (spec.hfRepo != null) {
      final siblings = await _hfSiblings(spec.hfRepo!);
      final prefix = spec.hfIncludePrefix ?? '';
      for (final s in siblings) {
        if (prefix.isNotEmpty && !s.startsWith(prefix)) continue;
        files.add(ModelFileItem(
          'https://huggingface.co/${spec.hfRepo}/resolve/main/$s',
          s,
        ));
      }
    }
    return files;
  }

  Future<List<String>> _hfSiblings(String repo) async {
    final resp =
        await _client.get(Uri.parse('https://huggingface.co/api/models/$repo'));
    if (resp.statusCode != 200) {
      throw HttpException('HF API ${resp.statusCode} for $repo');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return [
      for (final s in (json['siblings'] as List? ?? const []))
        (s as Map<String, dynamic>)['rfilename'] as String,
    ];
  }

  Stream<DownloadProgress> _streamToFile(String url, File dest) async* {
    final response = await _client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(
          total > 0 ? received / total : 0.0,
          '',
          received,
        );
      }
    } finally {
      await sink.close();
    }
  }

  static String _mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(0);

  void dispose() => _client.close();
}
