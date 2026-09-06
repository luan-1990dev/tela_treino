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
  // Inicializamos o mapa VAZIO para exibir apenas o que for válido
  Map<String, String> _allWorkoutTimes = {};

  Duration _grandTotalDuration = Duration.zero;
  bool _loadingTimes = true;

  @override
  void initState() {
    super.initState();
    // Chamamos o fetch de tempos que agora também atualizará a consistência
    _fetchAllWorkoutTimes();
  }

  DateTime get _startOfCurrentWeek {
    DateTime now = DateTime.now();
    int daysSinceSunday = now.weekday % 7;
    return DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceSunday));
  }

  Future<void> _fetchAllWorkoutTimes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('workouts')
          .where('lastUpdated', isGreaterThanOrEqualTo: _startOfCurrentWeek)
          .get();

      Map<String, String> validTimes = {}; // Mapa temporário para treinos com tempo
      Duration grandTotal = Duration.zero;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final List<dynamic> exercises = data['exercises'] ?? [];
        Duration workoutDuration = Duration.zero;

        for (var ex in exercises) {
          if (ex['startTime'] != null && ex['endTime'] != null) {
            DateTime start = (ex['startTime'] as Timestamp).toDate();
            DateTime end = (ex['endTime'] as Timestamp).toDate();

            if (start.isAfter(_startOfCurrentWeek)) {
              workoutDuration += end.difference(start);
            }
          }
        }

        // --- REGRA: Só adiciona se o treino teve algum exercício com tempo registrado ---
        if (workoutDuration > Duration.zero) {
          grandTotal += workoutDuration;
          String formatted = workoutDuration.inHours > 0
              ? "${workoutDuration.inHours}h ${workoutDuration.inMinutes % 60}min"
              : "${workoutDuration.inMinutes}min";

          validTimes[doc.id] = formatted;
        }
      }

      setState(() {
        _allWorkoutTimes = validTimes;
        _grandTotalDuration = grandTotal;
        // Dias ativos é o total de treinos que passaram no filtro acima
        _weeklyConsistency = validTimes.length;
        _loadingTimes = false;
      });
    } catch (e) {
      debugPrint("Erro ao buscar tempos: $e");
      setState(() => _loadingTimes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            _buildMainStat(grandTotalText, 'Tempo total na semana', Icons.auto_graph_rounded, Colors.blue),
            const SizedBox(height: 10),
            const Text(
              "Dados resetam todo domingo às 00:00",
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
            const SizedBox(height: 20),

            // --- SEÇÃO DE TEMPO POR TREINO FILTRADA ---
            Builder(
              builder: (context) {
                // Criamos a lista filtrada aqui para evitar erro de sintaxe
                final filteredEntries = _allWorkoutTimes.entries
                    .where((entry) => entry.value != '0m' && entry.value != '--:--')
                    .toList();

                return _buildStatCard(
                  title: 'Tempo por Treino (Esta Semana)',
                  items: filteredEntries.isEmpty
                      ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        "Nenhum treino realizado ainda.",
                        style: TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
                      ),
                    )
                  ]
                      : filteredEntries.map((entry) {
                    return _statRow(
                      'Treino ${entry.key}',
                      entry.value,
                      Icons.ads_click,
                      color: _getTreinoColor(entry.key),
                    );
                  }).toList(),
                );
              },
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

  // Função auxiliar para manter as cores originais dos treinos
  Color _getTreinoColor(String key) {
    switch (key) {
      case 'A': return Colors.orangeAccent;
      case 'B': return Colors.blueAccent;
      case 'C': return Colors.greenAccent;
      case 'D': return Colors.redAccent;
      default: return Colors.blue;
    }
  }

  // --- WIDGETS AUXILIARES ---
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