import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vibration/vibration.dart';
import '../models/exercise.dart';
import '../services/storage_service.dart';

class WorkoutScreen extends StatefulWidget {
  final String workoutKey;
  final String workoutTitle;
  const WorkoutScreen({required this.workoutKey, required this.workoutTitle, super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final StorageService _storage = StorageService();
  
  List<Exercise> _exercises = [];
  bool _isLoading = true;
  int _remainingSeconds = 0;
  Timer? _timer;
  bool _timerFinished = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadDataFromFirebase();
  }

  Future<void> _loadDataFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Se não houver usuário, carrega local (fallback)
      _loadLocalData();
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('workouts')
          .doc(widget.workoutKey)
          .get();

      if (snapshot.exists && snapshot.data() != null) {
        // Lógica de mapeamento do Firebase para o modelo Exercise
        // (Simplificado para este exemplo)
      } else {
        _loadLocalData();
      }
    } catch (e) {
      _loadLocalData();
    }
  }

  Future<void> _loadLocalData() async {
    // Implementação da carga local que já tínhamos
    setState(() => _isLoading = false);
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = seconds;
      _timerFinished = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _timer?.cancel();
        setState(() => _timerFinished = true);
        Vibration.vibrate(pattern: [500, 1000]);
      }
    });
  }

  // LÓGICA DE SCROLL AUTOMÁTICO INTELIGENTE
  void _scrollToNextPending() {
    int nextIndex = _exercises.indexWhere((e) => !e.seriesCompleted.every((c) => c));
    if (nextIndex != -1) {
      double offset = nextIndex * 350.0; // Estimativa da altura do card
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutQuart,
      );
    }
    setState(() => _timerFinished = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(widget.workoutTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            // Simulando lista de exercícios
            ..._exercises.map((ex) => _buildExerciseCard(ex)).toList(),
            const SizedBox(height: 100), // Espaço para o timer
          ],
        ),
      ),
      // BOTÃO DE RETORNO INTELIGENTE (Aparece só quando o timer acaba)
      floatingActionButton: _timerFinished 
        ? FloatingActionButton.extended(
            onPressed: _scrollToNextPending,
            label: const Text("VOLTAR AO TREINO"),
            icon: const Icon(Icons.keyboard_arrow_up),
            backgroundColor: Colors.blue,
          )
        : null,
      bottomNavigationBar: _buildBottomTimer(),
    );
  }

  Widget _buildExerciseCard(Exercise ex) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(ex.nameController.text),
      ),
    );
  }

  Widget _buildBottomTimer() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text("Descanso: ${_remainingSeconds}s", style: const TextStyle(fontSize: 18)),
          ElevatedButton(onPressed: () => _startTimer(60), child: const Text("60s")),
        ],
      ),
    );
  }
}
