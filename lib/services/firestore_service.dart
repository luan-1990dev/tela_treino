import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;

  // BACKUP COMPLETO (Incluindo Notas e Séries)
  Future<void> syncWorkoutToCloud({
    required String workoutKey, 
    required List<String> names, 
    required Map<int, List<bool>> seriesStates, 
    required Map<int, List<String>> repsLists, 
    required Map<int, List<String>> weightsLists,
    required Map<int, String> notesLists,
  }) async {
    if (uid == null) return;

    final workoutData = {
      'names': names,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    for (int i = 0; i < names.length; i++) {
      workoutData['ex_$i'] = {
        'series': seriesStates[i] ?? [],
        'reps': repsLists[i] ?? [],
        'weights': weightsLists[i] ?? [],
        'notes': notesLists[i] ?? '',
        'seriesCount': repsLists[i]?.length ?? 4,
      };
    }

    await _db
        .collection('users')
        .doc(uid)
        .collection('workouts')
        .doc(workoutKey)
        .set(workoutData, SetOptions(merge: true));
  }

  // CARREGAR BACKUP
  Future<DocumentSnapshot?> getWorkoutFromCloud(String workoutKey) async {
    if (uid == null) return null;
    return await _db
        .collection('users')
        .doc(uid)
        .collection('workouts')
        .doc(workoutKey)
        .get();
  }
}
