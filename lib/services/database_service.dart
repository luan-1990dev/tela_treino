import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'workout_history.db');
    return await openDatabase(
      path,
      version: 2, // Aumentado para migração
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE exercise_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_name TEXT,
            weight REAL,
            date TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE workout_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT,
            exercise_name TEXT,
            duration_seconds INTEGER,
            total_workout_time_seconds INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE workout_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT,
              exercise_name TEXT,
              duration_seconds INTEGER,
              total_workout_time_seconds INTEGER
            )
          ''');
        }
      },
    );
  }

  Future<void> insertHistory(String name, double weight) async {
    final db = await database;
    await db.insert('exercise_history', {
      'exercise_name': name,
      'weight': weight,
      'date': DateTime.now().toIso8601String(),
    });
  }

  Future<void> saveSessionData({
    required String exerciseName,
    required int durationSeconds,
    required int totalSeconds,
  }) async {
    final db = await database;
    await db.insert('workout_sessions', {
      'date': DateTime.now().toIso8601String(),
      'exercise_name': exerciseName,
      'duration_seconds': durationSeconds,
      'total_workout_time_seconds': totalSeconds,
    });
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    final db = await database;
    return await db.query('workout_sessions', orderBy: 'date DESC');
  }

  Future<List<Map<String, dynamic>>> getHistory(String name) async {
    final db = await database;
    return await db.query(
      'exercise_history',
      where: 'exercise_name = ?',
      whereArgs: [name],
      orderBy: 'date ASC',
    );
  }
}
