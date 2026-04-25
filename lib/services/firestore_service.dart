import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;

  // FORÇAR BACKUP COMPLETO
  Future<void> syncWorkoutToCloud({
    required String workoutKey,
    required String workoutTitle,
    required List<String> names,
    required Map<int, List<bool>> seriesStates,
    required Map<int, List<String>> repsLists,
    required Map<int, List<String>> weightsLists,
    required Map<int, String> notesLists,
  }) async {
    if (uid == null) return;

    final workoutData = {
      'workoutTitle': workoutTitle,
      'names': names,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    // Mapeia cada exercício para um objeto dentro do documento do treino
    for (int i = 0; i < names.length; i++) {
      workoutData['ex_$i'] = {
        'name': names[i],
        'series': seriesStates[i] ?? [],
        'reps': repsLists[i] ?? [],
        'weights': weightsLists[i] ?? [],
        'notes': notesLists[i] ?? '',
      };
    }

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('workouts')
          .doc(workoutKey)
          .set(workoutData, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      debugPrint("Erro Firestore [${e.code}]: ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("Erro genérico ao sincronizar: $e");
      rethrow;
    }
  }

  // CARREGAR BACKUP
  Future<DocumentSnapshot?> getWorkoutFromCloud(String workoutKey) async {
    if (uid == null) return null;
    try {
      return await _db
          .collection('users')
          .doc(uid)
          .collection('workouts')
          .doc(workoutKey)
          .get();
    } on FirebaseException catch (e) {
      debugPrint("Erro Firestore ao carregar [${e.code}]: ${e.message}");
      return null;
    } catch (e) {
      debugPrint("Erro genérico ao carregar backup: $e");
      return null;
    }
  }
}
