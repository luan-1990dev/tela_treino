import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  // CONFIGURAÇÃO DE SOM SELECIONADO
  Future<void> saveSelectedSound(String soundName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_sound', soundName);
  }

  Future<String> getSelectedSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_sound') ?? 'Notification';
  }

  // CONFIGURAÇÃO DE SOM ATIVADO
  Future<void> saveSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_enabled', enabled);
  }

  Future<bool> getSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('sound_enabled') ?? true;
  }

  // CONFIGURAÇÃO DE VIBRAÇÃO ATIVADA
  Future<void> saveVibrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_enabled', enabled);
  }

  Future<bool> getVibrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('vibration_enabled') ?? true;
  }

  Future<void> saveExerciseNames(String key, List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('workout_${key}_names', names);
  }

  Future<List<String>?> getExerciseNames(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('workout_${key}_names');
  }

  Future<void> saveWorkoutTitle(String key, String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_${key}_title', title);
  }

  Future<String?> getWorkoutTitle(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('workout_${key}_title');
  }

  Future<void> saveLastWelcomeDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_welcome_date', date);
  }

  Future<String?> getLastWelcomeDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_welcome_date');
  }

  Future<void> saveExerciseTimestamps(String key, int idx, DateTime? start, DateTime? end) async {
    final prefs = await SharedPreferences.getInstance();
    if (start != null) await prefs.setString('workout_${key}_ex_${idx}_start', start.toIso8601String());
    if (end != null) await prefs.setString('workout_${key}_ex_${idx}_end', end.toIso8601String());
  }

  Future<Map<String, DateTime?>> getExerciseTimestamps(String key, int idx) async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('workout_${key}_ex_${idx}_start');
    final endStr = prefs.getString('workout_${key}_ex_${idx}_end');
    return {
      'start': startStr != null ? DateTime.parse(startStr) : null,
      'end': endStr != null ? DateTime.parse(endStr) : null,
    };
  }

  Future<void> saveSeriesState(String key, int idx, List<bool> s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('workout_${key}_ex_${idx}_series', s.map((e) => e.toString()).toList());
  }

  Future<List<bool>?> getSeriesState(String key, int idx) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('workout_${key}_ex_${idx}_series')?.map((e) => e == 'true').toList();
  }

  Future<void> saveRepsList(String key, int idx, List<String> r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('workout_${key}_ex_${idx}_reps', r);
  }

  Future<List<String>?> getRepsList(String key, int idx) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('workout_${key}_ex_${idx}_reps');
  }

  Future<void> saveWeightsList(String key, int idx, List<String> w) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('workout_${key}_ex_${idx}_weights', w);
  }

  Future<List<String>?> getWeightsList(String key, int idx) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('workout_${key}_ex_${idx}_weights');
  }

  Future<void> saveSeriesCount(String key, int idx, int c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('workout_${key}_ex_${idx}_count', c);
  }

  Future<int?> getSeriesCount(String key, int idx) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('workout_${key}_ex_${idx}_count');
  }

  Future<void> saveExerciseNotes(String key, int idx, String notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_${key}_ex_${idx}_notes', notes);
  }

  Future<String?> getExerciseNotes(String key, int idx) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('workout_${key}_ex_${idx}_notes');
  }

  Future<void> savePrevWeight(String key, int idx, String w) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_${key}_ex_${idx}_prev', w);
  }

  Future<String?> getPrevWeight(String key, int idx) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('workout_${key}_ex_${idx}_prev');
  }

  Future<void> saveLastWorkout(String t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastWorkout', t);
  }

  Future<String?> getLastWorkout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('lastWorkout');
  }

  Future<void> clearAllWorkoutData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('workout_'));
    for (var k in keys) await prefs.remove(k);
  }
}
