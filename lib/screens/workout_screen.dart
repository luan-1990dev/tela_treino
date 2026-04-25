import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pip_view/pip_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';
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
  int _lastMarkedIndex = -1;
  Timer? _inactivityTimer;
  bool _hasShownMotivationalSnackBar = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  bool get wantKeepAlive => true;

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
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

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

  void _startInactivityMonitor() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) _showInactivitySnackBar();
    });
  }

  void _stopInactivityMonitor() => _inactivityTimer?.cancel();

  void _showInactivitySnackBar() {
    final screenHeight = MediaQuery.of(context).size.height;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      backgroundColor: Colors.orange.shade800,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.only(bottom: screenHeight / 2 - 40, left: 30, right: 30),
      content: const Text(
        "Como você está se sentindo?\nNão desista! Todo esforço vale a pena. 💪",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
      ),
    ));
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      bool nearBottom = _scrollController.offset > (_scrollController.position.maxScrollExtent - 150);
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<String> _getDefaultExercises(String key) {
    switch (key) {
      case 'A': return ['Supino reto', 'Pec deck', 'Crucifixo inclinado', 'Desenvolvimento maquina', 'Elevação lateral', 'Tríceps polia', 'Tríceps corda'];
      case 'B': return ['Puxador frontal aberto', 'Remada baixa', 'Puxada articulada', 'Remada alta', 'Encolhimento Halter', 'Rosca direta barra', 'Rosca alternada'];
      case 'C': return ['Leg Press', 'Extensora', 'Flexora sentada', 'Abdutora', 'Agachamento sumo', 'Panturrilha maquina', 'Panturrilha step'];
      case 'D': return ['Abdominal', 'Prancha', 'Agachamento livre', 'Flexão de braço', 'Burpee', 'Polichinelo', 'Elevação pélvica'];
      default: return ['Exercício novo'];
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
          final List<dynamic> exList = data['exercises'] ?? [];
          for (var item in exList) {
            final List<bool> completed = List<bool>.from(item['seriesCompleted'] ?? []);
            loadedExercises.add(Exercise(
              name: item['name'] ?? '',
              seriesCount: completed.length,
              initialReps: List<String>.from(item['reps'] ?? []),
              initialWeights: List<String>.from(item['weights'] ?? []),
              initialNotes: item['notes'] ?? '',
            )..seriesCompleted = completed);
          }
          final savedTitle = data['workoutTitle'];
          if (savedTitle != null) _titleController.text = savedTitle;
        }
      }

      if (loadedExercises.isEmpty) {
        List<String>? names = await _storage.getExerciseNames(widget.workoutKey);
        if (names == null || names.isEmpty) names = _getDefaultExercises(widget.workoutKey);
        final savedTitle = await _storage.getWorkoutTitle(widget.workoutKey);
        if (savedTitle != null) _titleController.text = savedTitle;

        for (int i = 0; i < names.length; i++) {
          final savedCount = await _storage.getSeriesCount(widget.workoutKey, i) ?? 4;
          final reps = await _storage.getRepsList(widget.workoutKey, i);
          final weights = await _storage.getWeightsList(widget.workoutKey, i);
          final notes = await _storage.getExerciseNotes(widget.workoutKey, i) ?? '';
          final ex = Exercise(name: names[i], seriesCount: savedCount, initialReps: reps, initialWeights: weights, initialNotes: notes);
          final series = await _storage.getSeriesState(widget.workoutKey, i);
          if (series != null) {
            ex.seriesCompleted = List.from(series);
            ex.updateSeriesCount(savedCount);
          }
          loadedExercises.add(ex);
        }
      }
      if (mounted) setState(() { _exercises = loadedExercises; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _autoSync() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('workouts').doc(widget.workoutKey).set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'workoutTitle': _titleController.text,
        'exercises': _exercises.map((e) => {
          'name': e.nameController.text,
          'seriesCompleted': e.seriesCompleted,
          'reps': e.repsControllers.map((c) => c.text).toList(),
          'weights': e.weightControllers.map((c) => c.text).toList(),
          'notes': e.notesController.text,
        }).toList(),
      }, SetOptions(merge: true));
    } catch (e) { debugPrint('Erro auto-sync: $e'); }
  }

  Future<void> _saveState(int index) async {
    if (index >= _exercises.length) return;
    final ex = _exercises[index];
    await _storage.saveWorkoutTitle(widget.workoutKey, _titleController.text);
    await _storage.saveExerciseNames(widget.workoutKey, _exercises.map((e) => e.nameController.text).toList());
    await _storage.saveSeriesState(widget.workoutKey, index, ex.seriesCompleted);
    await _storage.saveRepsList(widget.workoutKey, index, ex.repsControllers.map((c) => c.text).toList());
    await _storage.saveWeightsList(widget.workoutKey, index, ex.weightControllers.map((c) => c.text).toList());
    await _storage.saveSeriesCount(widget.workoutKey, index, ex.seriesCompleted.length);
    await _storage.saveExerciseNotes(widget.workoutKey, index, ex.notesController.text);
    _autoSync();

    if (_exercises.every((e) => e.seriesCompleted.every((c) => c)) && _exercises.isNotEmpty) {
      _showWorkoutCompleteSnackBar();
    }
  }

  void _showWorkoutCompleteSnackBar() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1B5E20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height / 2 - 80, left: 20, right: 20),
      content: const Column(mainAxisSize: MainAxisSize.min, children: [
        Text('🎉', style: TextStyle(fontSize: 40)),
        Text('Treino concluído!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        Text('Parabéns pela dedicação! 💪', style: TextStyle(fontSize: 14)),
      ]),
    ));
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 300);
  }

  void _showAlarmSettings() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(children: [Icon(Icons.tune, color: Colors.amber), SizedBox(width: 10), Text('Ajustes do Alarme', style: TextStyle(color: Colors.white, fontSize: 18))]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(title: const Text('Som', style: TextStyle(color: Colors.white70)), value: _timerService.useSound, activeColor: Colors.blue, onChanged: (v) { setState(() => _timerService.setSoundEnabled(v)); setDialogState(() {}); }),
              SwitchListTile(title: const Text('Vibração', style: TextStyle(color: Colors.white70)), value: _timerService.useVibration, activeColor: Colors.orange, onChanged: (v) { setState(() => _timerService.setVibrationEnabled(v)); setDialogState(() {}); }),
              const Divider(color: Colors.white12),
              const Text('ESCOLHER TOQUE', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
              _soundOption('Bipe Curto', 'Notification', setDialogState),
              _soundOption('Alarme Nativo', 'Alarm', setDialogState),
              _soundOption('Toque de Vidro', 'Glass', setDialogState),
              _soundOption('Campainha', 'Ringtone', setDialogState),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('FECHAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))],
        ),
      ),
    );
  }

  Widget _soundOption(String label, String value, StateSetter setDialogState) {
    return RadioListTile<String>(
      title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      value: value, groupValue: _timerService.selectedSoundType, activeColor: Colors.amber,
      onChanged: (v) { if (v != null) { setState(() => _timerService.setSelectedSound(v)); setDialogState(() {}); } },
    );
  }

  void _addNew() {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), title: const Text('Novo Exercício', style: TextStyle(color: Colors.white)), content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Nome do exercício', hintStyle: TextStyle(color: Colors.grey))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), TextButton(onPressed: () async { if (c.text.isNotEmpty) { setState(() { _exercises.add(Exercise(name: c.text, seriesCount: 4)); }); Navigator.pop(ctx); _autoSync(); } }, child: const Text('Adicionar'))]));
  }

  void _scrollToPending() {
    _timerService.stopVibration();
    _stopInactivityMonitor();
    int pendingIdx = _exercises.indexWhere((e) => !e.seriesCompleted.every((c) => c));
    if (pendingIdx != -1) {
      double scrollPos = (pendingIdx * 350.0);
      _scrollController.animateTo(scrollPos.clamp(0, _scrollController.position.maxScrollExtent), duration: const Duration(milliseconds: 800), curve: Curves.easeInOutQuart);
    }
  }

  void _requestRemove(int index) {
    final name = _exercises[index].nameController.text;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.orange, duration: const Duration(seconds: 15), behavior: SnackBarBehavior.floating, content: Column(mainAxisSize: MainAxisSize.min, children: [Text('Excluir "$name"?', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ElevatedButton(onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[200], foregroundColor: Colors.black), child: const Text('CANCELAR')), ElevatedButton(onPressed: () { ScaffoldMessenger.of(context).hideCurrentSnackBar(); setState(() => _exercises.removeAt(index)); _autoSync(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.black), child: const Text('SIM'))])])));
  }

  void _showNotesDialog(int index) {
    final ex = _exercises[index];
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: Text('Notas: ${ex.nameController.text}', style: const TextStyle(color: Colors.white, fontSize: 18)), content: TextField(controller: ex.notesController, maxLines: 3, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Configurações...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))), actions: [TextButton(onPressed: () { _saveState(index); Navigator.pop(ctx); }, child: const Text('SALVAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))]));
  }

  void _showHistoryChart(String name, int index) async {
    final history = await _db.getHistory(name);
    if (history.isEmpty) return;
    double current = _exercises[index].weightControllers.isNotEmpty ? (double.tryParse(_exercises[index].weightControllers.first.text) ?? 0) : 0;
    double prev = (history.length >= 2) ? (history[history.length-2]['weight'] as num).toDouble() : (history.first['weight'] as num).toDouble();
    if (mounted) {
      showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), title: Center(child: Text('Evolução: $name', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))), content: Container(height: 250, width: double.maxFinite, child: Column(children: [Expanded(child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: [FlSpot(0, prev), FlSpot(1, current)], isCurved: true, color: Colors.blue, barWidth: 5, dotData: const FlDotData(show: true))]))), const SizedBox(height: 12), Text('Anterior: ${prev}kg | Atual: ${current}kg', style: const TextStyle(color: Colors.white70, fontSize: 12))])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('VOLTAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))]));
    }
  }

  Future<void> _launchBenefitsSearch(String exerciseName) async {
    final query = 'Quais os benefícios e como executar o exercício ${exerciseName.toLowerCase()}';
    final uri = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchYouTubeSearch(String exerciseName) async {
    final query = 'Como fazer o exercício ${exerciseName.toLowerCase()}';
    final uri = Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final titleColor = theme.brightness == Brightness.dark ? Colors.white : Colors.black;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_showTimerButton && !_timerService.timerFinished)
              Padding(
                padding: const EdgeInsets.only(bottom: 85.0),
                child: FloatingActionButton.small(
                  onPressed: () => _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut),
                  backgroundColor: Colors.blue.withValues(alpha: 0.6),
                  child: const Icon(Icons.timer, color: Colors.white),
                  tooltip: 'Ir para Cronômetro',
                ),
              )
            else const SizedBox(width: 40),
            if (_timerService.timerFinished)
              Padding(
                padding: const EdgeInsets.only(bottom: 85.0),
                child: FloatingActionButton(
                  onPressed: _scrollToPending,
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.arrow_upward, color: Colors.white),
                  tooltip: 'Voltar para pendentes',
                ),
              ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () { SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); if (_timerService.timerFinished) _timerService.resetTimer(); else _timerService.stopVibration(); },
        child: PIPView(builder: (context, isFloating) => SingleChildScrollView(
          controller: _scrollController, padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                icon: const Icon(Icons.clear_all, color: Colors.orange, size: 32),
                onPressed: () => setState(() { for (var e in _exercises) { for (var j = 0; j < e.seriesCompleted.length; j++) e.seriesCompleted[j] = false; } _autoSync(); }),
                tooltip: 'Limpar todas as séries',
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 32),
                onPressed: _addNew,
                tooltip: 'Adicionar novo exercício',
              ),
              IconButton(
                icon: const Icon(Icons.my_library_music_sharp, color: Colors.deepPurple, size: 32),
                onPressed: _showAlarmSettings,
                tooltip: 'Ajustes de Som e Vibração',
              ),
            ]),
            TextField(controller: _titleController, textAlign: TextAlign.center, style: TextStyle(color: titleColor, fontSize: 24, fontWeight: FontWeight.bold), decoration: const InputDecoration(border: InputBorder.none), onChanged: (v) => _autoSync()),
            const Divider(height: 32),
            ...List.generate(_exercises.length, (idx) {
              final ex = _exercises[idx];
              return Card(
                key: ValueKey('ex_$idx'),
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: ex.seriesCompleted.every((c) => c) ? Colors.green : Colors.grey.shade400)),
                child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                  TextField(controller: ex.nameController, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), decoration: const InputDecoration(border: InputBorder.none), onChanged: (v) => _saveState(idx)),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () { setState(() => ex.updateSeriesCount(ex.seriesCompleted.length - 1)); _saveState(idx); }, tooltip: 'Remover série'),
                    Text('Séries: ${ex.seriesCompleted.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () { setState(() => ex.updateSeriesCount(ex.seriesCompleted.length + 1)); _saveState(idx); }, tooltip: 'Adicionar série'),
                  ]),

                  // --- LINHA DE ÍCONES RESTAURADA ---
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                      icon: const Icon(Icons.trending_up, color: Colors.green, size: 24),
                      onPressed: () => _showHistoryChart(ex.nameController.text, idx),
                      tooltip: 'Ver Evolução de Carga',
                    ),
                    IconButton(
                      icon: const Icon(Icons.ondemand_video, color: Colors.blueGrey, size: 24),
                      onPressed: () => _launchYouTubeSearch(ex.nameController.text),
                      tooltip: 'Ver Tutorial no YouTube',
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.blue, size: 24),
                      onPressed: () => _launchBenefitsSearch(ex.nameController.text),
                      tooltip: 'Benefícios e Execução (IA)',
                    ),
                    IconButton(
                      icon: const Icon(Icons.assignment_outlined, color: Colors.amber, size: 24),
                      onPressed: () => _showNotesDialog(idx),
                      tooltip: 'Minhas Notas Pessoais',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
                      onPressed: () => _requestRemove(idx),
                      tooltip: 'Excluir Exercício',
                    ),
                  ]),

                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(ex.seriesCompleted.length, (sIdx) => Checkbox(
                      value: ex.seriesCompleted[sIdx], activeColor: Colors.green,
                      onChanged: (v) { setState(() { ex.seriesCompleted[sIdx] = v ?? false; _stopInactivityMonitor(); }); _saveState(idx); }
                  ))),
                  const Divider(),
                  ...List.generate(ex.repsControllers.length, (idx2) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('Rep:'), SizedBox(width: 40, child: TextField(controller: ex.repsControllers[idx2], textAlign: TextAlign.center, keyboardType: TextInputType.number, onChanged: (v) => _saveState(idx))),
                    const SizedBox(width: 15),
                    const Text('Peso:'),
                    SizedBox(width: 65, child: TextField(controller: ex.weightControllers[idx2], textAlign: TextAlign.center, decoration: const InputDecoration(suffixText: 'kg', isDense: true), keyboardType: TextInputType.number, onChanged: (v) { _db.insertHistory(ex.nameController.text, double.tryParse(v) ?? 0); _saveState(idx); })),
                  ])),
                ])),
              );
            }),
            const SizedBox(height: 32),
            Column(children: [
              const Text('Descanso', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(icon: const Icon(Icons.remove_circle_outline, size: 36), onPressed: () => _timerService.adjustTimer(-10), tooltip: 'Diminuir 10s'),
                const SizedBox(width: 12),
                Stack(alignment: Alignment.center, children: [
                  SizedBox(height: 115, width: 115, child: CircularProgressIndicator(value: _timerService.initialSeconds > 0 ? _timerService.remainingSeconds / _timerService.initialSeconds : 0, strokeWidth: 8, backgroundColor: theme.colorScheme.surfaceContainerHighest, color: _timerService.remainingSeconds <= 10 && _timerService.remainingSeconds > 0 ? Colors.red : theme.colorScheme.primary)),
                  GestureDetector(onTap: () => _timerService.togglePause(), onLongPress: () => _timerService.resetTimer(), child: ScaleTransition(scale: _pulseAnimation, child: Text(_formattedTimerText, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _timerService.timerFinished ? (theme.brightness == Brightness.dark ? Colors.white : Colors.black) : ((_timerService.remainingSeconds > 0 && _timerService.remainingSeconds <= 10) ? Colors.red : theme.textTheme.bodyLarge?.color))))),
                ]),
                const SizedBox(width: 12),
                IconButton(icon: const Icon(Icons.add_circle_outline, size: 36), onPressed: () => _timerService.adjustTimer(10), tooltip: 'Aumentar 10s'),
              ]),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                FilledButton(onPressed: () => _timerService.startTimer(45), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade100, foregroundColor: Colors.black, shape: const StadiumBorder()), child: const Text('45s')),
                FilledButton(onPressed: () => _timerService.startTimer(60), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade400, shape: const StadiumBorder()), child: const Text('60s')),
                FilledButton(onPressed: () => _timerService.startTimer(90), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade800, shape: const StadiumBorder()), child: const Text('90s')),
                OutlinedButton(onPressed: () => _timerService.resetTimer(), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.grey), shape: const StadiumBorder()), child: const Text('Zerar')),
              ]),
              const SizedBox(height: 40),
            ]),
          ]),
        )),
      ),
    );
  }
}