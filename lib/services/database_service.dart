import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'workout_history.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE exercise_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_name TEXT,
            weight REAL,
            date TEXT
          )
        ''');
      },
    );
  }

  // Insere um novo registro de peso
  Future<void> insertHistory(String name, double weight) async {
    final db = await database;
    // Evita inserir duplicatas exatas seguidas (mesmo peso no mesmo dia)
    final lastEntry = await db.query(
      'exercise_history',
      where: 'exercise_name = ?',
      whereArgs: [name],
      orderBy: 'date DESC',
      limit: 1,
    );

    if (lastEntry.isEmpty || lastEntry.first['weight'] != weight) {
      await db.insert('exercise_history', {
        'exercise_name': name,
        'weight': weight,
        'date': DateTime.now().toIso8601String(),
      });
    }
  }

  // Busca o histórico formatado para o gráfico
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
