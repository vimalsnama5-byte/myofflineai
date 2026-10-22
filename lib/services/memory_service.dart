import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ChatMessageRecord {
  final String role; // 'user' | 'assistant'
  final String text;
  final int ts;
  const ChatMessageRecord(this.role, this.text, this.ts);
}

/// SQLite-backed conversation memory and key-value preferences.
class MemoryService {
  MemoryService._();
  static final MemoryService instance = MemoryService._();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final path = p.join(await getDatabasesPath(), 'packet_ai.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE messages(id INTEGER PRIMARY KEY AUTOINCREMENT,'
          ' role TEXT NOT NULL, text TEXT NOT NULL, ts INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE prefs(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    );
  }

  Future<void> addMessage(String role, String text) async {
    await _db!.insert('messages', {
      'role': role,
      'text': text,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Most recent [limit] messages in chronological order.
  Future<List<ChatMessageRecord>> recentMessages({int limit = 20}) async {
    final rows = await _db!.query(
      'messages',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed
        .map((r) => ChatMessageRecord(
            r['role'] as String, r['text'] as String, r['ts'] as int))
        .toList();
  }

  Future<void> clearHistory() async => _db!.delete('messages');

  Future<String?> getPref(String key) async {
    final rows =
        await _db!.query('prefs', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setPref(String key, String value) async {
    await _db!.insert('prefs', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
