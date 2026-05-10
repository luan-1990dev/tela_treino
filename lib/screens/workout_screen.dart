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

import '../models/exercise.dart';
import '../services/storage_service.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/timer_service.dart';

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

  List<Exercise> _exercises = [];
  bool _isLoading = true;
  bool _showTimerButton = true;

  // Controle de destaque e navegação
  int _manualActiveIndex = -1;
  int _lastMarkedIndex = -1;

  Timer? _inactivityTimer;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  bool get wantKeepAlive => true;

  // --- LÓGICA DE FOCO UNIFICADA (GETTER) ---
  int get _currentFocusIndex {
    // 1. Prioridade: Se o usuário clicou no GPS de um card manualmente
    if (_manualActiveIndex != -1) return _manualActiveIndex;

    // 2. Segunda opção: O primeiro exercício que ainda tem séries pendentes (seta >>)
    int firstPending = _exercises.indexWhere((e) =>
    !e.seriesCompleted.every((c) => c));
    if (firstPending != -1) return firstPending;

    // 3. Fallback: O último exercício que foi marcado
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
      if (_timerService.remainingSeconds <= 10 &&
          _timerService.remainingSeconds > 0 && !_timerService.isPaused) {
        if (!_pulseController.isAnimating) _pulseController.repeat(
            reverse: true);
      } else if (_timerService.timerFinished) {
        if (!_pulseController.isAnimating) _pulseController.repeat(
            reverse: true);
        if (_inactivityTimer == null) _startInactivityMonitor();
      } else {
        _pulseController.stop();
      }
    }
  }

  void _startInactivityMonitor() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) _showInactivitySnackBar();
    });
  }

  void _stopInactivityMonitor() => _inactivityTimer?.cancel();

  void _showInactivitySnackBar() {
    final screenHeight = MediaQuery
        .of(context)
        .size
        .height;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      backgroundColor: Colors.orange.shade800,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.only(
          bottom: screenHeight / 2 - 40, left: 30, right: 30),
      content: const Text(
        "Não desista! Todo esforço vale a pena. 💪",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
      ),
    ));
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      bool nearBottom = _scrollController.offset >
          (_scrollController.position.maxScrollExtent - 250);
      if (nearBottom && _showTimerButton)
        setState(() => _showTimerButton = false);
      else if (!nearBottom && !_showTimerButton) setState(() =>
      _showTimerButton = true);
    }
  }

  @override
  void dispose() {
    _timerService.removeListener(_onTimerTick);
    _scrollController.removeListener(_onScroll);
    _pulseController.dispose();
    _titleController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // --- LÓGICA DE SCROLL VINCULADA AO FOCO ---
  void _scrollToPending() {
    _timerService.stopVibration();
    _stopInactivityMonitor();

    int targetIdx = _currentFocusIndex;

    if (targetIdx != -1 && targetIdx < _exercises.length) {
      double scrollPos = (targetIdx * 350.0) - (MediaQuery
          .of(context)
          .size
          .height / 2) + 175.0;
      _scrollController.animateTo(
        scrollPos.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutQuart,
      );
    }
  }

  List<String> _getDefaultExercises(String key) {
    switch (key) {
      case 'A':
        return ['Supino reto', 'Pec deck', 'Elevação lateral', 'Tríceps polia'];
      case 'B':
        return [
          'Puxador frontal',
          'Remada baixa',
          'Rosca direta',
          'Rosca alternada'
        ];
      default:
        return ['Exercício 1', 'Exercício 2'];
    }
  }

  Future<void> _loadData() async {
    try {
      if (mounted) setState(() => _isLoading = true);
      final List<Exercise> loadedExercises = [];
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final cloudSnapshot = await _firestore.getWorkoutFromCloud(
            widget.workoutKey);
        if (cloudSnapshot != null && cloudSnapshot.exists) {
          final data = cloudSnapshot.data() as Map<String, dynamic>;
          final List<dynamic> exList = data['exercises'] ?? [];
          for (var item in exList) {
            final List<bool> completed = List<bool>.from(
                item['seriesCompleted'] ?? []);
            loadedExercises.add(Exercise(
              name: item['name'] ?? '',
              seriesCount: completed.length,
              initialReps: List<String>.from(item['reps'] ?? []),
              initialWeights: List<String>.from(item['weights'] ?? []),
              initialNotes: item['notes'] ?? '',
            )
              ..seriesCompleted = completed);
          }
          final savedTitle = data['workoutTitle'];
          if (savedTitle != null) _titleController.text = savedTitle;
        }
      }

      if (loadedExercises.isEmpty) {
        List<String>? names = await _storage.getExerciseNames(
            widget.workoutKey);
        if (names == null || names.isEmpty)
          names = _getDefaultExercises(widget.workoutKey);
        for (int i = 0; i < names.length; i++) {
          final savedCount = await _storage.getSeriesCount(
              widget.workoutKey, i) ?? 4;
          final reps = await _storage.getRepsList(widget.workoutKey, i);
          final weights = await _storage.getWeightsList(widget.workoutKey, i);
          final notes = await _storage.getExerciseNotes(widget.workoutKey, i) ??
              '';
          final ex = Exercise(name: names[i],
              seriesCount: savedCount,
              initialReps: reps,
              initialWeights: weights,
              initialNotes: notes);
          final series = await _storage.getSeriesState(widget.workoutKey, i);
          if (series != null) {
            ex.seriesCompleted = List.from(series);
            ex.updateSeriesCount(savedCount);
          }
          loadedExercises.add(ex);
        }
      }
      if (mounted) setState(() {
        _exercises = loadedExercises;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _autoSync() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('workouts')
          .doc(widget.workoutKey)
          .set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'workoutTitle': _titleController.text,
        'exercises': _exercises.map((e) =>
        {
          'name': e.nameController.text,
          'seriesCompleted': e.seriesCompleted,
          'reps': e.repsControllers.map((c) => c.text).toList(),
          'weights': e.weightControllers.map((c) => c.text).toList(),
          'notes': e.notesController.text,
        }).toList(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro auto-sync: $e');
    }
  }

  Future<void> _saveState(int index) async {
    if (index >= _exercises.length) return;
    final ex = _exercises[index];
    await _storage.saveWorkoutTitle(widget.workoutKey, _titleController.text);
    await _storage.saveExerciseNames(widget.workoutKey,
        _exercises.map((e) => e.nameController.text).toList());
    await _storage.saveSeriesState(
        widget.workoutKey, index, ex.seriesCompleted);
    await _storage.saveRepsList(widget.workoutKey, index,
        ex.repsControllers.map((c) => c.text).toList());
    await _storage.saveWeightsList(widget.workoutKey, index,
        ex.weightControllers.map((c) => c.text).toList());
    await _storage.saveSeriesCount(
        widget.workoutKey, index, ex.seriesCompleted.length);
    await _storage.saveExerciseNotes(
        widget.workoutKey, index, ex.notesController.text);
    _autoSync();

    if (_exercises.every((e) => e.seriesCompleted.every((c) => c)) &&
        _exercises.isNotEmpty) {
      _showWorkoutCompleteSnackBar();
    }
  }

  double _calculateCurrentTotalVolume() {
    double total = 0;
    for (var ex in _exercises) {
      for (int i = 0; i < ex.weightControllers.length; i++) {
        double r = double.tryParse(ex.repsControllers[i].text) ?? 0;
        double w = double.tryParse(ex.weightControllers[i].text) ?? 0;
        total += (r * w);
      }
    }
    return total;
  }

  Future<double> _calculatePreviousTotalVolume() async {
    double totalPrev = 0;
    for (var ex in _exercises) {
      final history = await _db.getHistory(ex.nameController.text);
      if (history.length >= 2) {
        double prevW = (history[history.length - 2]['weight'] as num)
            .toDouble();
        totalPrev += (prevW * 10 * ex.seriesCompleted.length);
      }
    }
    return totalPrev;
  }

  void _showWorkoutCompleteSnackBar() async {
    if (!mounted) return;
    final screenHeight = MediaQuery
        .of(context)
        .size
        .height;
    final currentVolume = _calculateCurrentTotalVolume();
    final previousVolume = await _calculatePreviousTotalVolume();
    final diff = currentVolume - previousVolume;

    Duration totalDuration = Duration.zero;
    for (var ex in _exercises) {
      if (ex.startTime != null && ex.endTime != null) {
        totalDuration += ex.endTime!.difference(ex.startTime!);
      }
    }

    int h = totalDuration.inHours;
    int m = totalDuration.inMinutes % 60;
    int s = totalDuration.inSeconds % 60;
    String timeString = h > 0 ? "$h h $m min $s seg" : "$m min $s seg";

    String emoji = diff > 0.5 ? '😁' : (diff < -0.5 ? '😔' : '😐');
    Color statusColor = diff > 0.5 ? Colors.greenAccent : (diff < -0.5 ? Colors
        .redAccent : Colors.white);
    String arrow = diff > 0.5 ? "↑" : (diff < -0.5 ? "↓" : "-");

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 15),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF0D47A1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.only(
          bottom: screenHeight / 2 - 100, left: 20, right: 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('Treino concluído!', style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
          Text('Tempo Total: $timeString',
              style: const TextStyle(fontSize: 14, color: Colors.white70)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(arrow, style: TextStyle(fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: statusColor)),
              const SizedBox(width: 8),
              Text('${currentVolume.toStringAsFixed(1)} kg', style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: statusColor)),
            ],
          ),
          Text('${diff.abs().toStringAsFixed(1)} kg ${diff > 0
              ? "aumento"
              : "diminuição"}', style: TextStyle(
              fontSize: 14, color: statusColor.withOpacity(0.8))),
          const SizedBox(height: 20),
          const Text('Parabéns pela dedicação! 💪', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70)),
        ],
      ),
    ));
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(
        duration: 400);
  }

  void _showAlarmSettings() {
    showDialog(
      context: context,
      builder: (ctx) =>
          StatefulBuilder(
            builder: (context, setDialogState) =>
                AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  title: const Row(children: [
                    Icon(Icons.library_music_rounded, color: Colors.deepPurple),
                    SizedBox(width: 10),
                    Text('Ajustes do Alarme',
                        style: TextStyle(color: Colors.white, fontSize: 18))
                  ]),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(title: const Text(
                          'Som', style: TextStyle(color: Colors.white70)),
                          value: _timerService.useSound,
                          activeColor: Colors.blue,
                          onChanged: (v) {
                            setState(() => _timerService.setSoundEnabled(v));
                            setDialogState(() {});
                          }),
                      SwitchListTile(title: const Text(
                          'Vibração', style: TextStyle(color: Colors.white70)),
                          value: _timerService.useVibration,
                          activeColor: Colors.orange,
                          onChanged: (v) {
                            setState(() =>
                                _timerService.setVibrationEnabled(v));
                            setDialogState(() {});
                          }),
                      const Divider(color: Colors.white12),
                      ListTile(
                        leading: const Icon(Icons.phonelink_setup_rounded,
                            color: Colors.greenAccent),
                        title: const Text('Som do Dispositivo',
                            style: TextStyle(
                                color: Colors.white, fontSize: 14)),
                        subtitle: Text(
                            _timerService.selectedSoundType == 'Custom'
                                ? 'Som personalizado ativo'
                                : 'Toque padrão', style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                        onTap: () => _pickCustomSound(setDialogState),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx),
                        child: const Text('FECHAR', style: TextStyle(
                            color: Colors.blue, fontWeight: FontWeight.bold)))
                  ],
                ),
          ),
    );
  }

  Future<void> _pickCustomSound(StateSetter setDialogState) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.audio, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        setState(() {
          _timerService.setSelectedSound('Custom');
          _timerService.setCustomSound(path);
        });
        setDialogState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Toque "${result.files.single.name}" selecionado! 🎵'),
            backgroundColor: Colors.green.shade900,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      debugPrint("Erro ao selecionar som: $e");
    }
  }

  void _addNew() {
    final c = TextEditingController();
    showDialog(context: context,
        builder: (ctx) =>
            AlertDialog(backgroundColor: const Color(0xFF1A1A1A),
                title: const Text(
                    'Novo Exercício', style: TextStyle(color: Colors.white)),
                content: TextField(controller: c,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        hintText: 'Nome do exercício',
                        hintStyle: TextStyle(color: Colors.grey))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  TextButton(onPressed: () async {
                    if (c.text.isNotEmpty) {
                      setState(() {
                        _exercises.add(Exercise(name: c.text, seriesCount: 4));
                      });
                      Navigator.pop(ctx);
                      _autoSync();
                    }
                  }, child: const Text('Adicionar'))
                ]));
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final Exercise item = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, item);
      _manualActiveIndex = -1;
    });
    _autoSync();
  }

  void _showNotesDialog(int index) {
    final ex = _exercises[index];
    showDialog(context: context,
        builder: (ctx) =>
            AlertDialog(backgroundColor: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Text('Notas: ${ex.nameController.text}',
                    style: const TextStyle(color: Colors.white, fontSize: 18)),
                content: TextField(controller: ex.notesController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(hintText: 'Configurações...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none))),
                actions: [TextButton(onPressed: () {
                  _saveState(index);
                  Navigator.pop(ctx);
                },
                    child: const Text('SALVAR', style: TextStyle(
                        color: Colors.blue, fontWeight: FontWeight.bold)))
                ]));
  }

  void _showHistoryChart(String name, int index) async {
    final history = await _db.getHistory(name);
    if (history.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ainda não há histórico para este exercício. 📈')));
      return;
    }
    final ex = _exercises[index];
    String durationText = '--:--';
    if (ex.startTime != null && ex.endTime != null) {
      final diff = ex.endTime!.difference(ex.startTime!);
      durationText = "${diff.inMinutes}m ${diff.inSeconds % 60}s";
    }
    double firstW = (history.first['weight'] as num).toDouble();
    double currentW = double.tryParse(ex.weightControllers.isNotEmpty
        ? ex.weightControllers.first.text
        : '0') ?? firstW;
    double projection = currentW +
        ((currentW - firstW) > 0 ? (currentW - firstW) * 0.2 : 2.0);

    showDialog(context: context, builder: (ctx) =>
        AlertDialog(
            backgroundColor: const Color(0xFF121212),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28)),
            title: Center(child: Text('Tendência: $name',
                style: const TextStyle(color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold))),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 180,
                  width: double.maxFinite,
                  child: LineChart(LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        show: true,
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(
                            showTitles: true, getTitlesWidget: (val, meta) {
                          if (val == 0) return const Text('INÍCIO',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 10));
                          if (val == 1) return const Text('HOJE',
                              style: TextStyle(
                                  color: Colors.blue, fontSize: 10));
                          if (val == 2) return const Text('META',
                              style: TextStyle(
                                  color: Colors.green, fontSize: 10));
                          return const SizedBox();
                        })),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(spots: [
                          FlSpot(0, firstW),
                          FlSpot(1, currentW),
                          FlSpot(2, projection)
                        ],
                            isCurved: true,
                            color: Colors.blue,
                            barWidth: 5,
                            dotData: const FlDotData(show: true))
                      ]))),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('Tempo', durationText),
                    _buildStat('Evolução',
                        '${(currentW - firstW).toStringAsFixed(1)}kg'),
                    _buildStat('Hoje', '${currentW}kg', valueColor: Colors.blue)
                  ])
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const Text('VOLTAR', style: TextStyle(
                      color: Colors.blue, fontWeight: FontWeight.bold)))
            ]
        ));
  }

  Widget _buildStat(String label, String value, {Color? valueColor}) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      Text(value, style: TextStyle(color: valueColor ?? Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold))
    ]);
  }

  Future<void> _launchBenefitsSearch(String name) async {
    final url = Uri.parse(
        'https://www.google.com/search?q=benefícios+exercício+${Uri
            .encodeComponent(name)}');
    if (await canLaunchUrl(url)) await launchUrl(
        url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final titleColor = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    // Identifica o índice do exercício ativo
    int activeIdx = _currentFocusIndex;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Stack(
          children: [
            if (_showTimerButton && !_timerService.timerFinished)
              Positioned(
                left: 0, bottom: 85.0,
                child: FloatingActionButton.small(
                  onPressed: () =>
                      _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                      ),
                  backgroundColor: Colors.blue.withValues(alpha: 0.6),
                  child: const Icon(Icons.timer, color: Colors.white),
                ),
              ),
            if (_timerService.timerFinished)
              Positioned(
                right: 10, bottom: 215.0,
                child: FloatingActionButton(
                  onPressed: _scrollToPending,
                  backgroundColor: Colors.deepOrange,
                  child: const Icon(Icons.arrow_upward, color: Colors.white),
                  tooltip: 'Voltar para o ativo',
                ),
              ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          if (_timerService.timerFinished)
            _timerService.resetTimer();
          else
            _timerService.stopVibration();
        },
        child: PIPView(
          builder: (context, isFloating) =>
              ReorderableListView.builder(
                scrollController: _scrollController,
                padding: const EdgeInsets.all(12.0),
                // Adicionamos +1 no count para o cronômetro no final
                itemCount: _exercises.length + 1,
                onReorder: (oldIdx, newIdx) {
                  if (oldIdx >= _exercises.length ||
                      newIdx >= _exercises.length) return;
                  _onReorder(oldIdx, newIdx);
                },
                header: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                      icon: const Icon(
                          Icons.clear_all, color: Colors.orange, size: 32),
                      onPressed: () =>
                          setState(() {
                            for (var e in _exercises) {
                              for (var j = 0; j < e.seriesCompleted.length; j++)
                                e.seriesCompleted[j] = false;
                            }
                            _autoSync();
                          }),
                    ),
                    IconButton(icon: const Icon(
                        Icons.add_circle_outline, color: Colors.blue, size: 32),
                        onPressed: _addNew),
                    IconButton(icon: const Icon(
                        Icons.my_library_music, color: Colors.deepPurple, size: 32),
                        onPressed: _showAlarmSettings),
                  ]),
                  TextField(
                    controller: _titleController,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: titleColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(border: InputBorder.none),
                    onChanged: (v) => _autoSync(),
                  ),
                  const Divider(height: 32),
                ]),
                itemBuilder: (context, idx) {
                  // SE FOR O ÚLTIMO ITEM: EXIBE O CRONÔMETRO
                  if (idx == _exercises.length) {
                    return Column(
                      key: const ValueKey('timer_footer'),
                      children: [
                        const SizedBox(height: 32),
                        const Text('Descanso', style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(icon: const Icon(
                                Icons.remove_circle_outline, size: 36),
                                onPressed: () =>
                                    _timerService.adjustTimer(-10)),
                            const SizedBox(width: 12),
                            Stack(alignment: Alignment.center, children: [
                              SizedBox(
                                height: 115, width: 115,
                                child: CircularProgressIndicator(
                                  value: _timerService.initialSeconds > 0
                                      ? _timerService.remainingSeconds /
                                      _timerService.initialSeconds
                                      : 0,
                                  strokeWidth: 8,
                                  backgroundColor: theme.colorScheme
                                      .surfaceContainerHighest,
                                  color: _timerService.remainingSeconds <= 10 &&
                                      _timerService.remainingSeconds > 0
                                      ? Colors.red
                                      : theme.colorScheme.primary,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _timerService.togglePause(),
                                onLongPress: () => _timerService.resetTimer(),
                                child: ScaleTransition(
                                  scale: _pulseAnimation,
                                  child: Text(_formattedTimerText,
                                      style: TextStyle(fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: (_timerService.timerFinished ||
                                              _timerService.remainingSeconds <=
                                                  10) ? Colors.red : theme
                                              .textTheme.bodyLarge?.color)),
                                ),
                              ),
                            ]),
                            const SizedBox(width: 12),
                            IconButton(icon: const Icon(
                                Icons.add_circle_outline, size: 36),
                                onPressed: () => _timerService.adjustTimer(10)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            FilledButton(onPressed: () =>
                                _timerService.startTimer(45),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.blue.shade100,
                                    foregroundColor: Colors.black,
                                    shape: const StadiumBorder()),
                                child: const Text('45s')),
                            FilledButton(onPressed: () =>
                                _timerService.startTimer(60),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.blue.shade400,
                                    shape: const StadiumBorder()),
                                child: const Text('60s')),
                            FilledButton(onPressed: () =>
                                _timerService.startTimer(90),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.blue.shade800,
                                    shape: const StadiumBorder()),
                                child: const Text('90s')),
                            OutlinedButton(onPressed: () =>
                                _timerService.resetTimer(),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.grey),
                                    shape: const StadiumBorder()),
                                child: const Text('Zerar')),
                          ],
                        ),
                        const SizedBox(height: 120),
                      ],
                    );
                  }

                  // CASO CONTRÁRIO: EXIBE O CARD DO EXERCÍCIO
                  final ex = _exercises[idx];
                  final bool isActive = idx == activeIdx;
                  return Card(
                    key: ValueKey('ex_$idx'),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: isActive
                        ? Colors.blue.withValues(alpha: 0.08)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: isActive ? Colors.deepOrange : (ex.seriesCompleted
                              .every((c) => c) ? Colors.green : Colors.grey
                              .shade400), width: isActive ? 2.5 : 1.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Column(mainAxisSize: MainAxisSize.min, children: [
                                Opacity(opacity: isActive ? 1.0 : 0.0,
                                    child: const Icon(
                                        Icons.double_arrow_outlined,
                                        color: Colors.deepOrange, size: 25)),
                                const SizedBox(height: 4),
                                GestureDetector(onTap: () {
                                  setState(() => _manualActiveIndex = idx);
                                  _timerService.stopVibration();
                                },
                                    child: Icon(
                                        isActive ? Icons.gps_fixed : Icons
                                            .gps_not_fixed,
                                        color: isActive ? Colors.deepOrange : Colors
                                            .grey.withValues(alpha: 0.5),
                                        size: 20)),
                              ]),
                              const SizedBox(width: 12),
                              Expanded(child: TextField(
                                  controller: ex.nameController,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: isActive ? Colors.deepOrange : null),
                                  decoration: const InputDecoration(
                                      border: InputBorder.none),
                                  onChanged: (v) => _saveState(idx))),
                            ]),
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    setState(() =>
                                        ex.updateSeriesCount(
                                            ex.seriesCompleted.length - 1));
                                    _saveState(idx);
                                  }),
                              Text('Séries: ${ex.seriesCompleted.length}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    setState(() =>
                                        ex.updateSeriesCount(
                                            ex.seriesCompleted.length + 1));
                                    _saveState(idx);
                                  }),
                            ]),
                        Row(mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(icon: const Icon(
                                  Icons.trending_up, color: Colors.green),
                                  onPressed: () =>
                                      _showHistoryChart(
                                          ex.nameController.text, idx)),
                              IconButton(icon: const Icon(
                                  Icons.ondemand_video, color: Colors.blueGrey),
                                  onPressed: () =>
                                      launchUrl(Uri.parse(
                                          'https://www.youtube.com/results?search_query=${ex
                                              .nameController.text}'),
                                          mode: LaunchMode
                                              .externalApplication)),
                              IconButton(icon: const Icon(
                                  Icons.info_outline, color: Colors.blue),
                                  onPressed: () =>
                                      _launchBenefitsSearch(
                                          ex.nameController.text)),
                              IconButton(icon: Icon(
                                  ex.notesController.text.isNotEmpty ? Icons
                                      .assignment : Icons.assignment_outlined,
                                  color: Colors.amber),
                                  onPressed: () => _showNotesDialog(idx)),
                              IconButton(icon: const Icon(
                                  Icons.delete_outline, color: Colors.red),
                                  onPressed: () =>
                                      setState(() {
                                        _exercises.removeAt(idx);
                                        _autoSync();
                                      })),
                            ]),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                              ex.seriesCompleted.length, (sIdx) =>
                              Checkbox(
                                value: ex.seriesCompleted[sIdx],
                                activeColor: Colors.green,
                                onChanged: (v) {
                                  setState(() {
                                    ex.seriesCompleted[sIdx] = v ?? false;
                                    if (v == true) {
                                      _lastMarkedIndex = idx;
                                      _manualActiveIndex = idx;
                                      _timerService.stopVibration();
                                      if (ex.startTime == null)
                                        ex.startTime = DateTime.now();
                                      if (ex.seriesCompleted.every((c) => c))
                                        ex.endTime = DateTime.now();
                                    }
                                    _stopInactivityMonitor();
                                  });
                                  _saveState(idx);
                                },
                              )),
                        ),
                        const Divider(),
                        ...List.generate(ex.repsControllers.length, (idx2) =>
                            Row(mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('Rep:'),
                                  SizedBox(width: 40,
                                      child: TextField(
                                          controller: ex.repsControllers[idx2],
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          onChanged: (v) => _saveState(idx))),
                                  const SizedBox(width: 15),
                                  const Text('Peso:'),
                                  SizedBox(width: 65,
                                      child: TextField(controller: ex
                                          .weightControllers[idx2],
                                          textAlign: TextAlign.center,
                                          decoration: const InputDecoration(
                                              suffixText: 'kg', isDense: true),
                                          keyboardType: TextInputType.number,
                                          onChanged: (v) {
                                            _db.insertHistory(
                                                ex.nameController.text,
                                                double.tryParse(v) ?? 0);
                                            _saveState(idx);
                                          })),
                                ])),
                      ]),


                    ),
                  );
                },
              ),
        ),
      ),
    );
  }
}