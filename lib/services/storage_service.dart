import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _lastWorkoutKey = 'lastWorkout';

  Future<void> saveLastWorkout(String workoutTitle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastWorkoutKey, workoutTitle);
  }

  Future<String?> getLastWorkout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastWorkoutKey);
  }

  Future<void> saveExerciseNames(String workoutKey, List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('workout_${workoutKey}_names', names);
  }

  Future<List<String>?> getExerciseNames(String workoutKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('workout_${workoutKey}_names');
  }

  Future<void> saveSeriesState(String workoutKey, int index, List<bool> series) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'workout_${workoutKey}_ex_${index}_series',
      series.map((s) => s.toString()).toList(),
    );
  }

  Future<List<bool>?> getSeriesState(String workoutKey, int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('workout_${workoutKey}_ex_${index}_series');
    return list?.map((s) => s == 'true').toList();
  }

  Future<void> saveRepsList(String workoutKey, int index, List<String> reps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('workout_${workoutKey}_ex_${index}_reps', reps);
  }

  Future<List<String>?> getRepsList(String workoutKey, int index) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('workout_${workoutKey}_ex_${index}_reps');
  }

  Future<void> saveWeightsList(String workoutKey, int index, List<String> weights) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('workout_${workoutKey}_ex_${index}_weights', weights);
  }

  Future<List<String>?> getWeightsList(String workoutKey, int index) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('workout_${workoutKey}_ex_${index}_weights');
  }

  // NOVO: Salvar quantidade de séries por exercício
  Future<void> saveSeriesCount(String workoutKey, int index, int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('workout_${workoutKey}_ex_${index}_series_count', count);
  }

  Future<int?> getSeriesCount(String workoutKey, int index) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('workout_${workoutKey}_ex_${index}_series_count');
  }

  Future<void> savePrevWeight(String workoutKey, int index, String weight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_${workoutKey}_ex_${index}_prev_weight', weight);
  }

  Future<String?> getPrevWeight(String workoutKey, int index) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('workout_${workoutKey}_ex_${index}_prev_weight');
  }

  Future<void> clearAllWorkoutData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith('workout_'));
    for (var key in keys) {
      await prefs.remove(key);
    }
  }
}
