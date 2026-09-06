import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pip_view/pip_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';
import 'package:file_picker/file_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/exercise.dart';
import '../services/storage_service.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/timer_service.dart';
import 'cardio_screen.dart';
import 'summary_screen.dart';

class WorkoutScreen extends StatefulWidget {
  final String workoutKey;
  final String workoutTitle;
  const WorkoutScreen({required this.workoutKey, required this.workoutTitle, super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final StorageService _storage = StorageService();
  final DatabaseService _db = DatabaseService();
  final FirestoreService _firestore = FirestoreService();
  final TimerService _timerService = TimerService();

  late final TextEditingController _titleController;
  late final TextEditingController _restTitleController;

  List<Exercise> _exercises = [];
  List<GlobalKey> _cardKeys = [];
  bool _isLoading = true;
  bool _showTimerButton = true;

  int _manualActiveIndex = -1;
  int _lastMarkedIndex = -1;

  Timer? _inactivityTimer;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  bool get wantKeepAlive => true;

  int get _currentFocusIndex {
    if (_manualActiveIndex != -1) return _manualActiveIndex;
    int firstPending = _exercises.indexWhere((e) => !e.seriesCompleted.every((c) => c));
    if (firstPending != -1) return firstPending;
    return _lastMarkedIndex;
  }

  String get _formattedTimerText {
    final m = _timerService.remainingSeconds ~/ 60;
    final s = _timerService.remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _titleController = TextEditingController(text: widget.workoutTitle);
    _restTitleController = TextEditingController(text: 'Descanso do treino');

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _timerService.addListener(_onTimerTick);
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  void _onTimerTick() {
    if (mounted) {
      setState(() {});
      if (_timerService.remainingSeconds <= 10 && _timerService.remainingSeconds > 0 && !_timerService.isPaused) {
        if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
      } else if (_timerService.timerFinished) {
        if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
        if (_inactivityTimer == null) _startInactivityMonitor();
      } else {
        _pulseController.stop();
      }
    }
  }

  Future<void> _launchMusicApp(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      bool launched = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
      if (!launched) throw 'Não foi possível abrir $url';
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("App não encontrado.")));
    }
  }

  void _stopInactivityMonitor() => _inactivityTimer?.cancel();
  void _startInactivityMonitor() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) _showInactivitySnackBar();
    });
  }

  void _showInactivitySnackBar() {
    final screenHeight = MediaQuery.of(context).size.height;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.orange.shade900,
      margin: EdgeInsets.only(bottom: screenHeight / 2 - 50, left: 40, right: 40),
      shape: const StadiumBorder(),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.bolt, color: Colors.amber),
          SizedBox(width: 12),
          Expanded(child: Text("Mantenha o foco! O treino ainda não acabou. 💪", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
        ],
      ),
    ));
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      bool nearBottom = _scrollController.offset > (_scrollController.position.maxScrollExtent - 250);
      if (nearBottom && _showTimerButton) setState(() => _showTimerButton = false);
      else if (!nearBottom && !_showTimerButton) setState(() => _showTimerButton = true);
    }
  }

  @override
  void dispose() {
    _timerService.removeListener(_onTimerTick);
    _scrollController.removeListener(_onScroll);
    _pulseController.dispose();
    _titleController.dispose();
    _restTitleController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scrollToPending() {
    _timerService.stopVibration();
    _stopInactivityMonitor();

    int targetIdx = _currentFocusIndex;
    // Verifica se o índice é válido
    if (targetIdx == -1 || targetIdx >= _exercises.length) return;

    setState(() {
      _manualActiveIndex = targetIdx;
    });

    // Tenta capturar o contexto do card através da GlobalKey
    final contextCard = _cardKeys[targetIdx].currentContext;

    if (contextCard != null) {
      // Se o card já está "renderizado" (perto da tela), o scroll é milimétrico
      Scrollable.ensureVisible(
        contextCard,
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeInOutCubic,
        alignment: 0.5, // Centraliza o card na tela
      ).then((_) => HapticFeedback.mediumImpact());
    } else {
      // FALLBACK: Se o card estiver muito longe (off-screen), o ReorderableListView
      // remove ele da árvore. Precisamos forçar o scroll por aproximação.
      // Aumentamos o multiplicador para 450.0 para compensar a altura do Dropset
      double estimatedPos = targetIdx * 450.0;
      _scrollController.animateTo(
        estimatedPos.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeInOutCubic,
      ).then((_) {
        // Após o scroll aproximado, tentamos centralizar novamente
        HapticFeedback.mediumImpact();
      });
    }
  }


  Future<void> _loadData() async {
    try {
      if (mounted) setState(() => _isLoading = true);
      final List<Exercise> loadedExercises = [];
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final cloudSnapshot = await _firestore.getWorkoutFromCloud(widget.workoutKey);
        if (cloudSnapshot != null && cloudSnapshot.exists) {
          final data = cloudSnapshot.data() as Map<String, dynamic>;
          if (data['restTitle'] != null) _restTitleController.text = data['restTitle'];
          if (data['workoutTitle'] != null) _titleController.text = data['workoutTitle'];
          final List<dynamic> exList = data['exercises'] ?? [];
          for (var item in exList) {
            final List<bool> completed = List<bool>.from(item['seriesCompleted'] ?? []);
            final ex = Exercise(
              name: item['name'] ?? '',
              seriesCount: completed.length,
              initialReps: List<String>.from(item['reps'] ?? []),
              initialWeights: List<String>.from(item['weights'] ?? []),
              initialNotes: item['notes'] ?? '',
            )..seriesCompleted = completed;
            if (item['startTime'] != null) ex.startTime = (item['startTime'] as Timestamp).toDate();
            if (item['endTime'] != null) ex.endTime = (item['endTime'] as Timestamp).toDate();
            loadedExercises.add(ex);
          }
        }
      }
      if (loadedExercises.isEmpty) {
        final exampleEx = Exercise(name: 'Agachamento livre', seriesCount: 4, initialReps: ['10', '10', '10', '10'], initialWeights: ['5', '10', '10', '15'], initialNotes: 'Exemplo de exercício.');
        exampleEx.seriesCompleted = [true, true, true, true];
        loadedExercises.add(exampleEx);
      }
      if (mounted) {
        setState(() {
          _exercises = loadedExercises;
          _cardKeys = List.generate(_exercises.length, (index) => GlobalKey());
          _isLoading = false;
        });
        _autoSync();
      }
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _autoSync() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('workouts').doc(widget.workoutKey).set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'workoutTitle': _titleController.text,
        'restTitle': _restTitleController.text,
        'exercises': _exercises.map((e) => {
          'name': e.nameController.text,
          'seriesCompleted': e.seriesCompleted,
          'reps': e.repsControllers.map((c) => c.text).toList(),
          'weights': e.weightControllers.map((c) => c.text).toList(),
          'notes': e.notesController.text,
          'startTime': e.startTime,
          'endTime': e.endTime,
        }).toList(),
      }, SetOptions(merge: true));
    } catch (e) { debugPrint('Erro auto-sync: $e'); }
  }

  Future<void> _saveState(int index) async {
    if (index >= _exercises.length) return;
    _autoSync();
    if (_exercises.every((e) => e.seriesCompleted.every((c) => c)) && _exercises.isNotEmpty) {
      _showWorkoutCompleteSnackBar();
    }
  }

  double _calculateCurrentTotalVolume() {
    double total = 0;
    for (var ex in _exercises) {
      for (int i = 0; i < ex.weightControllers.length; i++) {
        double pesoSoma = ex.weightControllers[i].text.split(',').map((e) => double.tryParse(e) ?? 0).fold(0, (a, b) => a + b);
        double r = double.tryParse(ex.repsControllers[i].text) ?? 0;
        total += (r * pesoSoma);
      }
    }
    return total;
  }

  Future<double> _calculatePreviousTotalVolume() async {
    double totalPrev = 0;
    for (var ex in _exercises) {
      final history = await _db.getHistory(ex.nameController.text);
      if (history.length >= 2) {
        double prevW = (history[history.length - 2]['weight'] as num).toDouble();
        totalPrev += (prevW * 10 * ex.seriesCompleted.length);
      } else if (history.isNotEmpty) {
        double prevW = (history.first['weight'] as num).toDouble();
        totalPrev += (prevW * 10 * ex.seriesCompleted.length);
      }
    }
    return totalPrev;
  }

  void _showWorkoutCompleteSnackBar() async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final currentVolume = _calculateCurrentTotalVolume();
    final previousVolume = await _calculatePreviousTotalVolume();
    final diff = currentVolume - previousVolume;

    Duration totalDuration = Duration.zero;
    for (var ex in _exercises) {
      if (ex.startTime != null && ex.endTime != null) {
        totalDuration += ex.endTime!.difference(ex.startTime!);
      }
    }
    String timeStr = "${totalDuration.inMinutes}m ${totalDuration.inSeconds % 60}s";

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF0D47A1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.only(bottom: screenHeight / 2 - 120, left: 20, right: 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏆', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('${_titleController.text} Concluído!'.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
          const Divider(color: Colors.white24, height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildSimpleStat('TEMPO', timeStr),
            _buildSimpleStat('TOTAL', '${currentVolume.toStringAsFixed(0)}kg'),
          ]),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
            child: Text('📈 Evolução: +${diff.toStringAsFixed(0)} kg', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          const Text('Parabéns pela dedicação! 💪', style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    ));
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 400);
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1)),
      Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
    ]);
  }

  void _showAlarmSettings() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.my_library_music, color: Colors.deepPurple, size: 32),
              SizedBox(width: 10),
              Text('Ajustes do Alarme', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Som', style: TextStyle(color: Colors.white70)),
                value: _timerService.useSound,
                activeColor: Colors.blue,
                onChanged: (v) {
                  setState(() => _timerService.setSoundEnabled(v));
                  setDialogState(() {});
                },
              ),
              SwitchListTile(
                title: const Text('Vibração', style: TextStyle(color: Colors.white70)),
                value: _timerService.useVibration,
                activeColor: Colors.orange,
                onChanged: (v) {
                  setState(() => _timerService.setVibrationEnabled(v));
                  setDialogState(() {});
                },
              ),
              const Divider(color: Colors.white10),
              // --- SELEÇÃO DE SOM NATIVO ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Toque:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    DropdownButton<String>(
                      value: _timerService.selectedSoundType,
                      dropdownColor: const Color(0xFF1A1A1A),
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      underline: const SizedBox(),
                      items: ['Notification', 'Alarm', 'Ringtone', 'Custom'].map((String val) {
                        return DropdownMenuItem<String>(
                          value: val,
                          child: Text(val == 'Notification' ? 'Notificação' :
                          val == 'Alarm' ? 'Alarme' :
                          val == 'Ringtone' ? 'Toque' : 'Arquivo...'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == 'Custom') {
                          _pickCustomSound(setDialogState);
                        } else if (v != null) {
                          setState(() => _timerService.setSelectedSound(v));
                          setDialogState(() {});
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('FECHAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }


  Future<void> _pickCustomSound(StateSetter setDialogState) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        setState(() { _timerService.setSelectedSound('Custom'); _timerService.setCustomSound(result.files.single.path!); });
        setDialogState(() {});
      }
    } catch (e) { debugPrint("Erro: $e"); }
  }

  void _addNew() {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), title: const Text('Novo Exercício', style: TextStyle(color: Colors.white)), content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Nome do exercício', hintStyle: TextStyle(color: Colors.grey))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), TextButton(onPressed: () async { if (c.text.isNotEmpty) { setState(() { _exercises.add(Exercise(name: c.text, seriesCount: 4)); _cardKeys.add(GlobalKey()); }); Navigator.pop(ctx); _autoSync(); } }, child: const Text('Adicionar'))]));
  }

  void _onReorder(int oldIdx, int newIdx) {
    setState(() {
      if (newIdx > oldIdx) newIdx -= 1;
      final item = _exercises.removeAt(oldIdx);
      _exercises.insert(newIdx, item);
      final key = _cardKeys.removeAt(oldIdx);
      _cardKeys.insert(newIdx, key);
      _manualActiveIndex = -1;
    });
    _autoSync();
  }

  void _showNotesDialog(int index) {
    final ex = _exercises[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Notas: ${ex.nameController.text}', style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: ex.notesController,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Configurações...',
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveState(index);
              Navigator.pop(ctx);
            },
            child: const Text('SALVAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showHistoryChart(String name, int index) async {
    final history = await _db.getHistory(name);
    final ex = _exercises[index];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    double todaySum = 0;
    double sumForAverage = 0;
    int countWeights = 0;
    for (var controller in ex.weightControllers) {
      double? val = double.tryParse(controller.text.split(',').first.replaceAll(',', '.'));
      if (val != null && val > 0) { todaySum += val; sumForAverage += val; countWeights++; }
    }
    if (todaySum == 0 && history.isNotEmpty) { todaySum = (history.last['weight'] as num).toDouble(); sumForAverage = todaySum; countWeights = 1; }
    if (todaySum == 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Insira o peso nas séries para ver a tendência. 📈'), behavior: SnackBarBehavior.floating));
      return;
    }
    double todayAverage = sumForAverage / countWeights;
    double goalSum = todaySum * 1.10;
    double perspective = goalSum - todaySum;
    String durationText = '--:--';
    if (ex.startTime != null && ex.endTime != null) {
      final diff = ex.endTime!.difference(ex.startTime!);
      durationText = "${diff.inMinutes}m ${diff.inSeconds % 60}s";
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Column(
          children: [
            Text('Gráfico de tendência', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 14)),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              SizedBox(
                height: 250,
                width: double.maxFinite,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: isDark ? Colors.white10 : Colors.black12,
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          getTitlesWidget: (v, m) => Text(
                            v.toStringAsFixed(0),
                            style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 10),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (v, m) {
                            final style = TextStyle(
                              color: isDark ? Colors.grey : Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            );
                            if (v == 0) return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('HOJE', style: style.copyWith(color: Colors.blue)));
                            if (v == 1) return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('META', style: style.copyWith(color: Colors.green)));
                            return const SizedBox();
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    minX: -0.1,
                    maxX: 1.1,
                    minY: (todaySum < goalSum ? todaySum : goalSum) * 0.95,
                    maxY: (todaySum > goalSum ? todaySum : goalSum) * 1.05,
                    lineBarsData: [
                      LineChartBarData(
                        spots: [FlSpot(0, todaySum), FlSpot(1, goalSum)],
                        isCurved: true,
                        color: Colors.blue,
                        barWidth: 6,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                            radius: 6,
                            color: Colors.blue,
                            strokeWidth: 2,
                            strokeColor: isDark ? const Color(0xFF121212) : Colors.white,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.withValues(alpha: 0.3),
                              Colors.blue.withValues(alpha: 0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('Tempo', durationText, isDark),
                    _buildStat('Perspectiva', '+${perspective.toStringAsFixed(1)}kg', isDark, valueColor: Colors.greenAccent),
                    _buildStat('Hoje (Média)', '${todayAverage.toStringAsFixed(1)}kg', isDark, valueColor: Colors.blue),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'VOLTAR',
              style: TextStyle(
                color: isDark ? Colors.blue : Colors.blue[700],
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, bool isDark, {Color? valueColor}) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: isDark ? Colors.grey : Colors.black45, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: valueColor ?? (isDark ? Colors.white : Colors.black87), fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTimeButton(String label, int seconds, Color bg, Color fg) {
    return FilledButton(onPressed: () => _timerService.startTimer(seconds), style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg, shape: const StadiumBorder()), child: Text(label));
  }
  Future<void> _launchBenefitsSearch(String name) async { final url = Uri.parse('https://www.google.com/search?q=benefícios+exercício+${Uri.encodeComponent(name)}'); if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication); }

  // Função auxiliar para criar a seção de peso centralizada ou expandida
  Widget _buildWeightSection(Exercise ex, int idx, int idx2, bool isDropset, List<String> subWeights) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('P:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        if (!isDropset)
          SizedBox(
            width: 55,
            child: TextField(
              controller: ex.weightControllers[idx2],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                suffixText: 'kg',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) {
                _db.insertHistory(ex.nameController.text, double.tryParse(v) ?? 0);
                _saveState(idx);
              },
            ),
          )
        else
          Row(
            children: List.generate(3, (subIdx) {
              return Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: TextField(
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: '${subIdx + 1}º',
                        hintStyle: const TextStyle(fontSize: 10),
                        isDense: true,
                        contentPadding: const EdgeInsets.all(6),
                      ),
                      onChanged: (v) {
                        List<String> weights = ex.weightControllers[idx2].text.split(',');
                        while (weights.length < 3) weights.add("");
                        weights[subIdx] = v;
                        ex.weightControllers[idx2].text = weights.join(',');
                        _saveState(idx);
                      },
                      controller: TextEditingController(
                          text: subWeights.length > subIdx ? subWeights[subIdx] : ""
                      )..selection = TextSelection.fromPosition(TextPosition(offset: (subWeights.length > subIdx ? subWeights[subIdx].length : 0))),
                    ),
                  ),
                  if (subIdx < 2)
                    const Icon(Icons.arrow_right_alt, size: 14, color: Colors.orange),
                ],
              );
            }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final titleColor = theme.brightness == Brightness.dark ? Colors.white : Colors.black;
    int activeIdx = _currentFocusIndex;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Stack(
          children: [
            if (_showTimerButton && !_timerService.timerFinished)
              Positioned(left: 0, bottom: 85.0, child: FloatingActionButton.small(onPressed: () => _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut), backgroundColor: Colors.blue.withValues(alpha: 0.6), child: const Icon(Icons.timer, color: Colors.white))),
            if (_timerService.timerFinished)
              Positioned(right: 10, bottom: 215.0, child: FloatingActionButton(onPressed: () => Future.delayed(const Duration(milliseconds: 50), () => _scrollToPending()), backgroundColor: Colors.deepOrange, child: const Icon(Icons.arrow_upward, color: Colors.white), tooltip: 'Voltar ao card ativo')),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () { SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); if (_timerService.timerFinished) _timerService.resetTimer(); else _timerService.stopVibration(); },
        child: PIPView(builder: (context, isFloating) => ReorderableListView.builder(
          scrollController: _scrollController,
          padding: const EdgeInsets.all(12.0),
          itemCount: _exercises.length + 1,
          onReorder: _onReorder,
          header: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const FaIcon(FontAwesomeIcons.spotify, color: Color(0xFF1DB954), size: 22), onPressed: () => _launchMusicApp('spotify:'), tooltip: 'Spotify'),
              IconButton(icon: const FaIcon(FontAwesomeIcons.youtube, color: Color(0xFFFF0000), size: 22), onPressed: () => _launchMusicApp('https://music.youtube.com'), tooltip: 'YT Music'),
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.brightness == Brightness.light ? Colors.black.withOpacity(0.1) : Colors.white24, width: 1.0)),
                child: IconButton(constraints: const BoxConstraints(), padding: const EdgeInsets.all(8), icon: FaIcon(FontAwesomeIcons.apple, color: theme.brightness == Brightness.light ? Colors.black : Colors.white, size: 20), onPressed: () => _launchMusicApp('music:'), tooltip: 'Apple Music'),
              ),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.clear_all, color: Colors.orange, size: 28), onPressed: () => setState(() { for (var e in _exercises) { for (var j = 0; j < e.seriesCompleted.length; j++) e.seriesCompleted[j] = false; } _autoSync(); }), tooltip: 'Limpar progresso'),
              IconButton(icon: ScaleTransition(scale: _pulseAnimation, child: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 28)), onPressed: () { _pulseController.stop(); _addNew(); }, tooltip: 'Adicionar exercício'),
              IconButton(icon: const Icon(Icons.my_library_music, color: Colors.deepPurple, size: 28), onPressed: _showAlarmSettings, tooltip: 'Ajustes de Som'),
              IconButton(icon: const Icon(Icons.analytics_outlined, color: Colors.greenAccent, size: 28), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SummaryScreen(exercises: _exercises))), tooltip: 'Resumo'),
            ]),
            Tooltip(
              message: 'Toque para renomear este treino',
              child: TextField(
                controller: _titleController,
                textAlign: TextAlign.center,
                style: TextStyle(color: titleColor, fontSize: 24, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Nome do Treino'),
                onChanged: (v) => _autoSync(),
              ),
            ),
            const Divider(height: 24),
          ]),
          itemBuilder: (context, idx) {
            if (idx == _exercises.length) {
              return Column(key: const ValueKey('timer_footer'), children: [
                const SizedBox(height: 32),
                const Text('Cronômetro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 25)),
                const SizedBox(height: 4),
                SizedBox(width: 250, child: TextField(controller: _restTitleController, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey), decoration: const InputDecoration(hintText: 'Nome do descanso', border: InputBorder.none, isDense: true), onChanged: (v) => _autoSync())),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildTimeButton('45s', 45, Colors.blue.shade100, Colors.black), _buildTimeButton('60s', 60, Colors.blue.shade400, Colors.white), _buildTimeButton('90s', 90, Colors.blue.shade800, Colors.white)]),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(icon: const Icon(Icons.remove_circle_outline, size: 36), onPressed: () => _timerService.adjustTimer(-10)),
                  const SizedBox(width: 12),
                  Stack(alignment: Alignment.center, children: [
                    SizedBox(height: 115, width: 115, child: CircularProgressIndicator(value: _timerService.initialSeconds > 0 ? _timerService.remainingSeconds / _timerService.initialSeconds : 0, strokeWidth: 8, backgroundColor: theme.colorScheme.surfaceContainerHighest, color: _timerService.remainingSeconds <= 10 && _timerService.remainingSeconds > 0 ? Colors.red : theme.colorScheme.primary)),
                    GestureDetector(onTap: () => _timerService.togglePause(), onLongPress: () => _timerService.resetTimer(), child: ScaleTransition(scale: _pulseAnimation, child: Text(_formattedTimerText, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: (_timerService.timerFinished || _timerService.remainingSeconds <= 10) ? Colors.red : theme.textTheme.bodyLarge?.color)))),
                  ]),
                  const SizedBox(width: 12),
                  IconButton(icon: const Icon(Icons.add_circle_outline, size: 36), onPressed: () => _timerService.adjustTimer(10)),
                ]),
                const SizedBox(height: 20),
                OutlinedButton(onPressed: () => _timerService.resetTimer(), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.grey), shape: const StadiumBorder()), child: const Text('Zerar Cronômetro')),
                const SizedBox(height: 30),
                const Divider(color: Colors.white12, indent: 40, endIndent: 40),
                const SizedBox(height: 20),
                GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CardioScreen(workoutKey: widget.workoutKey))), child: Column(children: [
                  const RunningCardioIcon(),
                  const SizedBox(height: 8),
                  Text('CARDIO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                ])),
                const SizedBox(height: 120),
              ]);
            }

            final ex = _exercises[idx];
            final bool isActive = idx == activeIdx;
            double opacity = (activeIdx != -1 && !isActive) ? 0.4 : 1.0;

            return AnimatedOpacity(
              key: _cardKeys[idx],
              duration: const Duration(milliseconds: 500),
              opacity: opacity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isActive ? Colors.deepOrange : (ex.seriesCompleted.every((c) => c) ? Colors.green : Colors.grey.shade400), width: isActive ? 3.5 : 2.0),
                  boxShadow: isActive ? [BoxShadow(color: Colors.deepOrange.withOpacity(0.3), blurRadius: 15, spreadRadius: 2)] : [],
                ),
                child: Card(
                  elevation: 0,
                  color: isActive ? Colors.deepOrange.withValues(alpha: 0.05) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Opacity(opacity: isActive ? 1.0 : 0.0, child: const Icon(Icons.double_arrow_outlined, color: Colors.deepOrange, size: 25)),
                          const SizedBox(height: 4),
                          GestureDetector(onTap: () { setState(() => _manualActiveIndex = idx); _timerService.stopVibration(); }, child: Icon(isActive ? Icons.gps_fixed : Icons.gps_not_fixed, color: isActive ? Colors.deepOrange : Colors.grey.withValues(alpha: 0.5), size: 20)),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: ex.nameController, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isActive ? Colors.deepOrange : titleColor), decoration: const InputDecoration(border: InputBorder.none), onChanged: (v) => _saveState(idx))),
                      ]),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () { setState(() => ex.updateSeriesCount(ex.seriesCompleted.length - 1)); _saveState(idx); }),
                        Text('Séries: ${ex.seriesCompleted.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () { setState(() => ex.updateSeriesCount(ex.seriesCompleted.length + 1)); _saveState(idx); }),
                      ]),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(icon: const Icon(Icons.trending_up, color: Colors.green), onPressed: () => _showHistoryChart(ex.nameController.text, idx)),
                        IconButton(icon: const Icon(Icons.ondemand_video, color: Colors.blueGrey), onPressed: () => launchUrl(Uri.parse('https://www.youtube.com/results?search_query=${ex.nameController.text}'), mode: LaunchMode.externalApplication)),
                        IconButton(icon: const Icon(Icons.info_outline, color: Colors.blue), onPressed: () => launchUrl(Uri.parse('https://www.google.com/search?q=benefícios+exercício+${Uri.encodeComponent(ex.nameController.text)}'))),
                        IconButton(icon: Icon(ex.notesController.text.isNotEmpty ? Icons.assignment : Icons.assignment_outlined, color: Colors.amber), onPressed: () => _showNotesDialog(idx)),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() { _exercises.removeAt(idx); _cardKeys.removeAt(idx); _autoSync(); })),
                      ]),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: Wrap(alignment: WrapAlignment.center, spacing: 0, runSpacing: 0, children: List.generate(ex.seriesCompleted.length, (sIdx) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Checkbox(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            value: ex.seriesCompleted[sIdx],
                            activeColor: Colors.green,
                            onChanged: (v) {
                              setState(() {
                                ex.seriesCompleted[sIdx] = v ?? false;
                                if (v == true) {
                                  _lastMarkedIndex = idx;
                                  _manualActiveIndex = idx;
                                  _timerService.stopVibration();
                                  bool isFirstMarked = ex.seriesCompleted.where((c) => c).length == 1;
                                  if (isFirstMarked) { ex.startTime = DateTime.now(); ex.endTime = null; }
                                  if (ex.seriesCompleted.every((c) => c)) {
                                    ex.endTime = DateTime.now();
                                    if (_exercises.every((e) => e.seriesCompleted.every((c) => c))) _showWorkoutCompleteSnackBar();
                                  }
                                }
                                _stopInactivityMonitor();
                              });
                              _saveState(idx);
                            },
                          ),
                        );
                      }))),
                      const Divider(),
                      ...List.generate(ex.repsControllers.length, (idx2) {
                        // Lógica para identificar se é Dropset
                        bool isDropset = ex.weightControllers[idx2].text.contains(',');
                        List<String> subWeights = ex.weightControllers[idx2].text.split(',');

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.white.withOpacity(0.03) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            // Centraliza tudo se NÃO for dropset. Se for, alinha à esquerda para o Expanded funcionar.
                            mainAxisAlignment: isDropset ? MainAxisAlignment.start : MainAxisAlignment.center,
                            children: [
                              // 1. Número da Série
                              Text('${idx2 + 1}º',
                                  style: TextStyle(fontSize: 11, color: isActive ? Colors.deepOrange : Colors.grey)),
                              const SizedBox(width: 10),

                              // 2. Campo de Repetições
                              const Text('R:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              SizedBox(
                                width: 40,
                                child: TextField(
                                  controller: ex.repsControllers[idx2],
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.deepOrange)),
                                  ),
                                  onChanged: (v) => _saveState(idx),
                                ),
                              ),

                              const SizedBox(width: 8),

                              // 3. Botão Dropset (DS)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isDropset) {
                                      ex.weightControllers[idx2].text = subWeights[0];
                                    } else {
                                      ex.weightControllers[idx2].text = "${ex.weightControllers[idx2].text},,";
                                    }
                                  });
                                  _saveState(idx);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDropset ? Colors.orange : Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: isDropset ? Colors.orange : Colors.white24),
                                  ),
                                  child: const Text("DS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ),

                              const SizedBox(width: 8),

                              // 4. Seção de Pesos
                              // Se for Dropset, usa Expanded para ocupar o espaço e permitir scroll
                              if (isDropset)
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: _buildWeightSection(ex, idx, idx2, isDropset, subWeights),
                                  ),
                                )
                              else
                              // Se não for Dropset, renderiza apenas o conteúdo (mantém centralizado)
                                _buildWeightSection(ex, idx, idx2, isDropset, subWeights),
                            ],
                          ),
                        );
                      }),
                    ]),
                  ),
                ),
              ),
            );
          },
        )),
      ),
    );
  }
}

class RunningCardioIcon extends StatefulWidget {
  const RunningCardioIcon({super.key});

  @override
  State<RunningCardioIcon> createState() => _RunningCardioIconState();
}

class _RunningCardioIconState extends State<RunningCardioIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _tiltAnimation;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);

    _tiltAnimation = Tween<double>(begin: -0.1, end: 0.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _bounceAnimation = Tween<double>(begin: 0, end: -8.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.bounceIn),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _bounceAnimation.value),
          child: Transform.rotate(
            angle: _tiltAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.2),
                    blurRadius: 15,
                    spreadRadius: _controller.value * 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_run_rounded,
                size: 40,
                color: Colors.green,
              ),
            ),
          ),
        );
      },
    );
  }
}