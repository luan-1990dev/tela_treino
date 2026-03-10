import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pip_view/pip_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import '../models/exercise.dart';
import '../services/storage_service.dart';
import '../services/database_service.dart';

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
  
  List<Exercise> _exercises = [];
  bool _isLoading = true;
  Timer? _timer;
  int _remainingSeconds = 0;
  int _initialSeconds = 0;
  bool _timerFinished = false;
  bool _isPaused = false;
  Timer? _vibrationTimer;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(_pulseController);
    
    _scrollController.addListener(() => setState(() {}));
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (mounted) setState(() => _isLoading = true);
      List<String>? names = await _storage.getExerciseNames(widget.workoutKey);
      if (names == null || names.isEmpty) {
        names = ['Supino reto', 'Pec deck', 'Elevação lateral'];
        await _storage.saveExerciseNames(widget.workoutKey, names);
      }
      final loaded = <Exercise>[];
      for (int i = 0; i < names.length; i++) {
        final savedCount = await _storage.getSeriesCount(widget.workoutKey, i) ?? 4;
        final reps = await _storage.getRepsList(widget.workoutKey, i);
        final weights = await _storage.getWeightsList(widget.workoutKey, i);
        final ex = Exercise(name: names[i], seriesCount: savedCount, initialReps: reps, initialWeights: weights);
        final series = await _storage.getSeriesState(widget.workoutKey, i);
        if (series != null) {
          ex.seriesCompleted = List.from(series);
          ex.updateSeriesCount(savedCount);
        }
        loaded.add(ex);
      }
      if (mounted) setState(() { _exercises = loaded; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _exercises = []; _isLoading = false; });
    }
  }

  Future<void> _saveState(int index) async {
    if (index >= _exercises.length) return;
    final ex = _exercises[index];
    await _storage.saveExerciseNames(widget.workoutKey, _exercises.map((e) => e.nameController.text).toList());
    await _storage.saveSeriesState(widget.workoutKey, index, ex.seriesCompleted);
    await _storage.saveRepsList(widget.workoutKey, index, ex.repsControllers.map((c) => c.text).toList());
    await _storage.saveWeightsList(widget.workoutKey, index, ex.weightControllers.map((c) => c.text).toList());
    await _storage.saveSeriesCount(widget.workoutKey, index, ex.seriesCompleted.length);
    
    if (_exercises.every((e) => e.seriesCompleted.every((c) => c))) {
      _showWorkoutCompleteSnackBar();
    }
  }

  void _showWorkoutCompleteSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      backgroundColor: Colors.blue.shade800,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.emoji_events, color: Colors.amber, size: 32),
        SizedBox(height: 8),
        Text('Treino concluído com sucesso, Parabéns!!!\nAgora beba muita água, se alimente bem e descanse.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ]),
    ));
  }

  void _startTimer(int s) {
    _stopVibration();
    _timer?.cancel();
    setState(() { _remainingSeconds = s; _initialSeconds = s; _timerFinished = false; _isPaused = false; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _isPaused) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          if (_remainingSeconds <= 10) _pulseController.repeat(reverse: true);
        } else {
          _timer?.cancel(); _timerFinished = true; _pulseController.stop();
          _startContinuousVibration();
        }
      });
    });
  }

  void _startContinuousVibration() {
    _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      Vibration.vibrate(pattern: [500, 1000]);
    });
  }

  void _stopVibration() {
    _vibrationTimer?.cancel();
    Vibration.cancel();
  }

  void _resetTimer() {
    _stopVibration();
    _timer?.cancel(); _pulseController.stop();
    setState(() { _remainingSeconds = 0; _initialSeconds = 0; _timerFinished = false; _isPaused = false; });
  }

  void _adjustTimer(int s) {
    setState(() {
      _remainingSeconds = (_remainingSeconds + s).clamp(0, 999);
      if (_initialSeconds < _remainingSeconds) _initialSeconds = _remainingSeconds;
    });
    if ((_timer == null || !_timer!.isActive) && _remainingSeconds > 0) _startTimer(_remainingSeconds);
  }

  void _scrollToNextPending() {
    _stopVibration();
    int nextIndex = _exercises.indexWhere((e) => !e.seriesCompleted.every((c) => c));
    if (nextIndex != -1) {
      _scrollController.animateTo(nextIndex * 350.0, duration: const Duration(milliseconds: 800), curve: Curves.easeInOutQuart);
    }
    setState(() => _timerFinished = false);
  }

  Future<void> _launchYouTubeSearch(String exerciseName) async {
    final query = 'Treino em FOCO como fazer ${exerciseName.toLowerCase()}';
    final uri = Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showHistoryChart(String name) async {
    final history = await _db.getHistory(name);
    if (history.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('Evolução: $name'),
      content: SizedBox(height: 300, width: double.maxFinite, child: LineChart(LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        lineBarsData: [LineChartBarData(spots: history.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['weight'] as double)).toList(), isCurved: true, color: Colors.blue)],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
    ));
  }

  void _requestRemove(int index) {
    final name = _exercises[index].nameController.text;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.orange, duration: const Duration(seconds: 15), behavior: SnackBarBehavior.floating,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Excluir o exercício "$name"?', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ElevatedButton(onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[200], foregroundColor: Colors.black), child: const Text('CANCELAR')),
          ElevatedButton(onPressed: () { ScaffoldMessenger.of(context).hideCurrentSnackBar(); setState(() => _exercises.removeAt(index)); _saveState(0); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.black), child: const Text('SIM')),
        ]),
      ]),
    ));
  }

  void _addNew() {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Novo Exercício'),
      content: TextField(controller: c, autofocus: true, inputFormatters: [LengthLimitingTextInputFormatter(19)]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        TextButton(onPressed: () async {
          if (c.text.isNotEmpty) {
            final names = _exercises.map((e) => e.nameController.text).toList()..add(c.text);
            await _storage.saveExerciseNames(widget.workoutKey, names);
            Navigator.pop(ctx);
            _loadData();
          }
        }, child: const Text('Adicionar'))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    bool showQuickJump = _scrollController.hasClients && _scrollController.offset < (_scrollController.position.maxScrollExtent - 200);

    return Scaffold(
      floatingActionButton: Stack(
        children: [
          // BOTÃO ESQUERDA: Atalho para cronômetro
          if (showQuickJump)
            Positioned(
              left: 32,
              bottom: 16,
              child: FloatingActionButton.small(
                onPressed: () => _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut),
                backgroundColor: Colors.blue.withValues(alpha: 0.6),
                child: const Icon(Icons.timer, color: Colors.white),
              ),
            ),
          // BOTÃO DIREITA: Retorno inteligente após timer
          if (_timerFinished)
            Positioned(
              right: 0,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: _scrollToNextPending,
                backgroundColor: Colors.blue,
                child: const Icon(Icons.arrow_upward, color: Colors.white),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () { if (_timerFinished) _resetTimer(); else _stopVibration(); },
        child: PIPView(builder: (context, isFloating) => SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.clear_all, color: Colors.orange, size: 32), onPressed: () => setState(() { for (var e in _exercises) e.seriesCompleted = List.filled(e.seriesCompleted.length, false); })),
              IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 32), onPressed: _addNew),
            ]),
            const Divider(height: 32),
            ReorderableListView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _exercises.length,
              onReorder: (oldIdx, newIdx) { setState(() { if (newIdx > oldIdx) newIdx -= 1; final item = _exercises.removeAt(oldIdx); _exercises.insert(newIdx, item); }); },
              itemBuilder: (context, idx) {
                final ex = _exercises[idx];
                return Card(
                  key: ValueKey('ex_$idx'), margin: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: ex.seriesCompleted.every((c) => c) ? Colors.green : Colors.grey.shade400)),
                  child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                    Text(ex.nameController.text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(icon: const Icon(Icons.remove_circle_outline, size: 24, color: Colors.grey), onPressed: () { setState(() => ex.updateSeriesCount(ex.seriesCompleted.length - 1)); _saveState(idx); }),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)), child: Text('Séries: ${ex.seriesCompleted.length}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      IconButton(icon: const Icon(Icons.add_circle_outline, size: 24, color: Colors.blue), onPressed: () { setState(() => ex.updateSeriesCount(ex.seriesCompleted.length + 1)); _saveState(idx); }),
                    ]),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(icon: const Icon(Icons.trending_up, color: Colors.green, size: 24), onPressed: () => _showHistoryChart(ex.nameController.text)),
                      IconButton(icon: const Icon(Icons.ondemand_video, color: Colors.blueGrey, size: 24), onPressed: () => _launchYouTubeSearch(ex.nameController.text)),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 24), onPressed: () => _requestRemove(idx)),
                    ]),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(ex.seriesCompleted.length, (sIdx) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(height: 24, width: 24, child: Checkbox(value: ex.seriesCompleted[sIdx], activeColor: Colors.green, onChanged: (v) { setState(() { ex.seriesCompleted[sIdx] = v ?? false; if (v!) _startTimer(60); }); _saveState(idx); })),
                    ))),
                    const Divider(height: 24),
                    ...List.generate(ex.repsControllers.length, (sIdx) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CircleAvatar(radius: 10, child: Text('${sIdx + 1}', style: const TextStyle(fontSize: 10))),
                        const SizedBox(width: 12),
                        const Text('Rep:'),
                        SizedBox(width: 35, child: TextField(controller: ex.repsControllers[sIdx], textAlign: TextAlign.center, decoration: const InputDecoration(isDense: true), keyboardType: TextInputType.number, onChanged: (v) => _saveState(idx))),
                        const SizedBox(width: 16),
                        const Text('Peso:'),
                        SizedBox(width: 45, child: TextField(controller: ex.weightControllers[sIdx], textAlign: TextAlign.center, decoration: const InputDecoration(isDense: true, suffixText: 'kg'), keyboardType: TextInputType.number, onChanged: (v) { _db.insertHistory(ex.nameController.text, double.tryParse(v) ?? 0); _saveState(idx); })),
                      ]),
                    )),
                  ])),
                );
              },
            ),
            const SizedBox(height: 32),
            const Text('Descanso', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.remove_circle_outline, size: 32), onPressed: () => _adjustTimer(-10)),
              const SizedBox(width: 16),
              Stack(alignment: Alignment.center, children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 4)),
                  child: SizedBox(height: 110, width: 110, child: CircularProgressIndicator(value: _initialSeconds > 0 ? _remainingSeconds / _initialSeconds : 0, strokeWidth: 8, color: _remainingSeconds <= 10 && _remainingSeconds > 0 ? Colors.red : theme.colorScheme.primary)),
                ),
                GestureDetector(onTap: () => setState(() => _isPaused = !_isPaused), onLongPress: _resetTimer, child: ScaleTransition(scale: _pulseAnimation, child: Text('${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)))),
              ]),
              const SizedBox(width: 16),
              IconButton(icon: const Icon(Icons.add_circle_outline, size: 32), onPressed: () => _adjustTimer(10)),
            ]),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              FilledButton(onPressed: () => _startTimer(45), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade100, foregroundColor: Colors.black), child: const Text('45s')),
              FilledButton(onPressed: () => _startTimer(60), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade400), child: const Text('60s')),
              FilledButton(onPressed: () => _startTimer(90), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade800), child: const Text('90s')),
              OutlinedButton(onPressed: _resetTimer, style: OutlinedButton.styleFrom(foregroundColor: Colors.red), child: const Text('Zerar')),
            ]),
          ]),
        )),
      ),
    );
  }
}
