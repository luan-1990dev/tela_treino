import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/exercise.dart';

class SummaryScreen extends StatefulWidget {
  final List<Exercise> exercises;
  const SummaryScreen({super.key, required this.exercises});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  int _weeklyConsistency = 0;
  Map<String, String> _allWorkoutTimes = {
    'A': '--:--',
    'B': '--:--',
    'C': '--:--',
    'D': '--:--',
  };

  Duration _grandTotalDuration = Duration.zero;
  bool _loadingTimes = true;

  @override
  void initState() {
    super.initState();
    _fetchWeeklyConsistency();
    _fetchAllWorkoutTimes();
  }

  // LÓGICA DE RESET: Calcula o início da semana atual (último domingo às 00:00)
  DateTime get _startOfCurrentWeek {
    DateTime now = DateTime.now();
    // No Dart, weekday vai de 1 (Segunda) a 7 (Domingo)
    // Se hoje é domingo (7), subtraímos 0 dias para pegar o início de hoje.
    // Se hoje é segunda (1), subtraímos 1 dia para chegar no domingo.
    int daysSinceSunday = now.weekday % 7;
    return DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceSunday));
  }

  Future<void> _fetchAllWorkoutTimes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Filtramos para buscar apenas treinos atualizados após o último domingo 00:00
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('workouts')
          .where('lastUpdated', isGreaterThanOrEqualTo: _startOfCurrentWeek)
          .get();

      Map<String, String> times = {'A': '0m', 'B': '0m', 'C': '0m', 'D': '0m'};
      Duration grandTotal = Duration.zero;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final List<dynamic> exercises = data['exercises'] ?? [];
        Duration workoutDuration = Duration.zero;

        for (var ex in exercises) {
          if (ex['startTime'] != null && ex['endTime'] != null) {
            DateTime start = (ex['startTime'] as Timestamp).toDate();
            DateTime end = (ex['endTime'] as Timestamp).toDate();
            // Só somamos se o início do exercício também foi dentro desta semana
            if (start.isAfter(_startOfCurrentWeek)) {
              workoutDuration += end.difference(start);
            }
          }
        }

        grandTotal += workoutDuration;

        String formatted;
        if (workoutDuration.inHours > 0) {
          formatted = "${workoutDuration.inHours}h ${workoutDuration.inMinutes % 60}min";
        } else {
          formatted = "${workoutDuration.inMinutes}min";
        }

        times[doc.id] = formatted;
      }

      setState(() {
        _allWorkoutTimes = times;
        _grandTotalDuration = grandTotal;
        _loadingTimes = false;
      });
    } catch (e) {
      debugPrint("Erro ao buscar tempos: $e");
      setState(() => _loadingTimes = false);
    }
  }

  Future<void> _fetchWeeklyConsistency() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Consistency também filtrada pelo início da semana (Domingo)
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .where('lastUpdated', isGreaterThanOrEqualTo: _startOfCurrentWeek)
        .get();

    setState(() {
      _weeklyConsistency = snapshot.docs.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    double totalVolume = 0;
    int totalReps = 0;
    int totalSeries = 0;
    Exercise? heaviestExercise;
    Exercise? fastestExercise;
    double maxWeight = 0;
    Duration minDuration = const Duration(hours: 24);

    for (var ex in widget.exercises) {
      bool exStarted = false;
      Duration exDuration = Duration.zero;

      if (ex.startTime != null && ex.endTime != null) {
        // Verifica se o treino atual (o que o usuário acabou de fazer) é válido
        exDuration = ex.endTime!.difference(ex.startTime!);
        exStarted = true;
      }

      for (int i = 0; i < ex.seriesCompleted.length; i++) {
        if (ex.seriesCompleted[i]) {
          double r = double.tryParse(ex.repsControllers[i].text) ?? 0;
          double w = double.tryParse(ex.weightControllers[i].text) ?? 0;
          totalVolume += (r * w);
          totalReps += r.toInt();
          totalSeries++;

          if (w > maxWeight) {
            maxWeight = w;
            heaviestExercise = ex;
          }
        }
      }

      if (exStarted && exDuration < minDuration && exDuration > Duration.zero) {
        minDuration = exDuration;
        fastestExercise = ex;
      }
    }

    String grandTotalText = _grandTotalDuration.inHours > 0
        ? "${_grandTotalDuration.inHours}h ${_grandTotalDuration.inMinutes % 60}min"
        : "${_grandTotalDuration.inMinutes}min";

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Resumo Semanal', style: TextStyle(fontSize: 18)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Card Maior com a soma da SEMANA
            _buildMainStat(grandTotalText, 'Tempo total na semana', Icons.auto_graph_rounded, Colors.blue),
            const SizedBox(height: 10),
            Text(
              "Dados resetam todo domingo às 00:00",
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
            const SizedBox(height: 20),

            _buildStatCard(
              title: 'Tempo por Treino (Esta Semana)',
              items: [
                _statRow('Treino A', _allWorkoutTimes['A']!, Icons.ads_click, color: Colors.orangeAccent),
                _statRow('Treino B', _allWorkoutTimes['B']!, Icons.ads_click, color: Colors.blueAccent),
                _statRow('Treino C', _allWorkoutTimes['C']!, Icons.ads_click, color: Colors.greenAccent),
                _statRow('Treino D', _allWorkoutTimes['D']!, Icons.ads_click, color: Colors.redAccent),
              ],
            ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildSmallStat('${totalVolume.toStringAsFixed(0)} kg', 'Volume hoje', Icons.fitness_center, Colors.orange)),
                const SizedBox(width: 15),
                Expanded(child: _buildSmallStat('$_weeklyConsistency', 'Dias ativos/Semana', Icons.calendar_month, Colors.purpleAccent)),
              ],
            ),
            const SizedBox(height: 15),
            _buildStatCard(
              title: 'Engajamento (Sessão Atual)',
              items: [
                _statRow('Séries concluídas', '$totalSeries', Icons.inventory_2_outlined),
                _statRow('Repetições totais', '$totalReps', Icons.tag),
                _statRow('Média por exercício', '${totalSeries > 0 ? (totalVolume / widget.exercises.length).toStringAsFixed(1) : 0} kg', Icons.balance),
              ],
            ),
            const SizedBox(height: 15),
            _buildStatCard(
              title: 'Destaques do Dia',
              items: [
                _statRow('Mais pesado', heaviestExercise?.nameController.text ?? '-', Icons.bolt, color: Colors.redAccent),
                _statRow('Mais rápido', fastestExercise?.nameController.text ?? '-', Icons.speed, color: Colors.greenAccent),
              ],
            ),
            const SizedBox(height: 30),
            const Text('Foco total na missão! 🔥', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // Os widgets auxiliares (_buildMainStat, _buildSmallStat, etc) permanecem os mesmos...
  Widget _buildMainStat(String value, String label, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 45),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), letterSpacing: 1.2, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSmallStat(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildStatCard({required String title, required List<Widget> items}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 15),
          ...items,
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.white24),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}