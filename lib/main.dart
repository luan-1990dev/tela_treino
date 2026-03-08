import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pip_view/pip_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

import 'package:tela_treino/models/exercise.dart';
import 'package:tela_treino/services/storage_service.dart';
import 'package:tela_treino/services/database_service.dart';

final themeManager = ValueNotifier<ThemeMode>(ThemeMode.dark);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeManager,
      builder: (context, currentMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'App de Treino',
          theme: ThemeData(colorSchemeSeed: Colors.blue, brightness: Brightness.light, useMaterial3: true),
          darkTheme: ThemeData(colorSchemeSeed: Colors.blue, brightness: Brightness.dark, useMaterial3: true),
          themeMode: currentMode,
          home: const MyHomePage(title: 'Plano de Treino'),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {});
    });
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _storage.saveLastWorkout('Treino ${String.fromCharCode(65 + _tabController.index)}');
      }
    });
    _showLastWorkoutSnackBar();
  }

  void _showLastWorkoutSnackBar() {
    Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final last = await _storage.getLastWorkout();
      if (last != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).size.height / 2 - 60),
          backgroundColor: Colors.orange,
          content: Text('Último treino: $last', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        ));
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(theme.brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => themeManager.value = theme.brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.colorScheme.primary, width: 2)),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withAlpha(179),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [Tab(text: 'Treino A'), Tab(text: 'Treino B'), Tab(text: 'Treino C'), Tab(text: 'Treino D')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          WorkoutScreen(workoutKey: 'A', workoutTitle: 'Peito, ombro e tríceps'),
          WorkoutScreen(workoutKey: 'B', workoutTitle: 'Costas, trapézio e bíceps'),
          WorkoutScreen(workoutKey: 'C', workoutTitle: 'Pernas e panturrilhas'),
          WorkoutScreen(workoutKey: 'D', workoutTitle: 'Funcional / Cardio'),
        ],
      ),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  final String workoutKey;
  final String workoutTitle;
  const WorkoutScreen({required this.workoutKey, required this.workoutTitle, super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

final ScrollController _scrollController = ScrollController();
class _WorkoutScreenState extends State<WorkoutScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  final StorageService _storage = StorageService();
  final DatabaseService _db = DatabaseService();
  late final TextEditingController _workoutTitleController;
  late List<Exercise> _exercises;
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workoutTitleController = TextEditingController(text: widget.workoutTitle);
    _loadData();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(_pulseController);
  }

  Future<void> _loadData() async {
    List<String>? names = await _storage.getExerciseNames(widget.workoutKey);
    if (names == null || names.isEmpty) {
      names = _getDefaultExercises(widget.workoutKey);
      await _storage.saveExerciseNames(widget.workoutKey, names);
    }

    final loaded = <Exercise>[];
    for (int i = 0; i < names.length; i++) {
      final savedCount = await _storage.getSeriesCount(widget.workoutKey, i) ?? 4;
      final reps = await _storage.getRepsList(widget.workoutKey, i);
      final weights = await _storage.getWeightsList(widget.workoutKey, i);
      
      final ex = Exercise(name: names[i], seriesCount: savedCount, initialReps: reps, initialWeights: weights);
      
      final series = await _storage.getSeriesState(widget.workoutKey, i);
      if (series != null && series.length == ex.seriesCompleted.length) ex.seriesCompleted = series;
      
      ex.previousWeight = await _storage.getPrevWeight(widget.workoutKey, i) ?? '';
      loaded.add(ex);
    }
    if (mounted) setState(() { _exercises = loaded; _isLoading = false; });
  }

  Future<void> _saveState(int index) async {
    if (index >= _exercises.length) return;
    final ex = _exercises[index];
    await _storage.saveExerciseNames(widget.workoutKey, _exercises.map((e) => e.nameController.text).toList());
    await _storage.saveSeriesState(widget.workoutKey, index, ex.seriesCompleted);
    await _storage.saveRepsList(widget.workoutKey, index, ex.repsControllers.map((c) => c.text).toList());
    await _storage.saveWeightsList(widget.workoutKey, index, ex.weightControllers.map((c) => c.text).toList());
    await _storage.saveSeriesCount(widget.workoutKey, index, ex.repsControllers.length);

    if (ex.seriesCompleted.every((c) => c)) {
      await _storage.savePrevWeight(widget.workoutKey, index, ex.weightControllers.isNotEmpty ? ex.weightControllers.first.text : '0');
    }

    if (_exercises.every((e) => e.seriesCompleted.every((c) => c))) {
      _showWorkoutCompleteSnackBar();
    }

    _checkReset();
  }

  void _showWorkoutCompleteSnackBar() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: Colors.blue.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events, color: Colors.amber, size: 32),
            SizedBox(height: 8),
            Text(
              'Treino concluído com sucesso, Parabéns!!!\nAgora beba muita água, se alimente bem e descanse.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkReset() async {
    bool all = true;
    for (final key in ['A', 'B', 'C', 'D']) {
      final names = await _storage.getExerciseNames(key) ?? [];
      for (int i = 0; i < names.length; i++) {
        final series = await _storage.getSeriesState(key, i);
        if (series == null || series.any((s) => !s)) { all = false; break; }
      }
      if (!all) break;
    }
    if (all) {
      await _storage.clearAllWorkoutData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text('Ciclo completo! Reiniciado.', textAlign: TextAlign.center)));
        _loadData();
      }
    }
  }
  
  void _clearAllSeries() {
    setState(() {
      for (int i = 0; i < _exercises.length; i++) {
        for (int j = 0; j < _exercises[i].seriesCompleted.length; j++) {
          _exercises[i].seriesCompleted[j] = false;
        }
        _saveState(i);
      }
    });
  }

  void _addNew() {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Novo Exercício'),
      content: TextField(
        controller: c,
        autofocus: true,
        inputFormatters: [LengthLimitingTextInputFormatter(19)],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        TextButton(onPressed: () async {
          if (c.text.isNotEmpty) {
            final names = _exercises.map((e) => e.nameController.text).toList()..add(c.text);
            await _storage.saveExerciseNames(widget.workoutKey, names);
            Navigator.pop;
            _loadData();
          }
        }, child: const Text('Adicionar'))
      ],
    ));
  }

  void _requestRemove(int index) {
    final name = _exercises[index].nameController.text;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: isDark ? Colors.black : Colors.white,
      duration: const Duration(seconds: 15),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Excluir o exercício "$name"?', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ElevatedButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[200],
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black, width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('CANCELAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              _remove(index);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black, width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: const Text('SIM', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
      ]),
    ));
  }

  Future<void> _remove(int index) async {
    setState(() { _exercises.removeAt(index); });
    await _storage.saveExerciseNames(widget.workoutKey, _exercises.map((e) => e.nameController.text).toList());
    _loadData();
  }

  Future<void> _launchYouTubeSearch(String exerciseName) async {
    final query = 'Treino em FOCO como fazer ${exerciseName.toLowerCase()}';
    final uri = Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o YouTube.')));
    }
  }

  Future<void> _showHistoryChart(String name) async {
    final history = await _db.getHistory(name);
    if (history.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sem histórico para este exercício.')));
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Evolução: $name'),
          content: SizedBox(
            height: 300,
            width: double.maxFinite,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: history.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['weight'] as double)).toList(),
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 4,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
        ),
      );
    }
  }

  List<String> _getDefaultExercises(String key) {
    if (key == 'A') return ['Supino reto', 'Pec deck', 'Crucifixo inclinado', 'Desenvolvimento maquina', 'Elevação lateral', 'Tríceps polia', 'Tríceps corda'];
    if (key == 'B') return ['Puxador frontal aberto', 'Remada baixa', 'Puxada articulada', 'Remada alta', 'Encolhimento Halter', 'Rosca direta barra', 'Rosca alternada'];
    if (key == 'C') return ['Leg Press', 'Extensora', 'Flexora sentada', 'Abdutora', 'Agachamento sumo', 'Panturrilha maquina', 'Panturrilha step'];
    return ['Abdominal', 'Prancha', 'Agachamento livre', 'Flexão de braço', 'Burpee', 'Polichinelo', 'Elevação pélvica'];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _vibrationTimer?.cancel();
    _pulseController.dispose();
    _workoutTitleController.dispose();

    // Corrigido: Envolvido em um bloco {} conforme a regra de lint
    for (var ex in _exercises) {
      ex.dispose();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _remainingSeconds > 0) {
      PIPView.of(context)?.presentBelow(_buildPip());
    } else if (state == AppLifecycleState.resumed) {
      PIPView.of(context)?.dispose();
    }
  }

  void _startTimer(int s) {
    _vibrationTimer?.cancel(); _pulseController.stop(); _timer?.cancel();
    setState(() { _remainingSeconds = s; _initialSeconds = s; _timerFinished = false; _isPaused = false; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _isPaused) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          if (_remainingSeconds <= 10) _pulseController.repeat(reverse: true);
        } else {
          _timer?.cancel(); _timerFinished = true; _pulseController.stop();
          Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
          _vibrationTimer = Timer.periodic(const Duration(seconds: 3), (vt) => Vibration.vibrate(pattern: [500, 1000, 500, 1000]));
        }
      });
    });
  }

  void _resetTimer() {
    _vibrationTimer?.cancel(); _timer?.cancel(); _pulseController.stop();
    setState(() { _remainingSeconds = 0; _initialSeconds = 0; _timerFinished = false; _isPaused = false; });
  }

  void _adjustTimer(int s) {
    setState(() {
      _remainingSeconds = (_remainingSeconds + s).clamp(0, 999);
      if (_initialSeconds < _remainingSeconds) _initialSeconds = _remainingSeconds;
    });
    if ((_timer == null || !_timer!.isActive) && _remainingSeconds > 0) {
      _startTimer(_remainingSeconds);
    }
  }

  void _togglePause() {
    setState(() { _isPaused = !_isPaused; });
  }

  Widget _buildPip() => Center(
    child: Text(
      _timerText,
      style: TextStyle(
        fontSize: 32, //
        fontWeight: FontWeight.bold,
        // Fica vermelho se faltar entre 1 e 10 segundos
        color: (_remainingSeconds > 0 && _remainingSeconds <= 10)
            ? Colors.red
            : Colors.black,
      ),
    ),
  );

  String get _timerText {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _scrollController.hasClients && _scrollController.offset > (_scrollController.position.maxScrollExtent - 100)
          ? null // Esconde o botão se já estiver no final da tela
          : Padding(
        padding: const EdgeInsets.only(bottom: 60.0), // Sobe o botão em 60 pixels
        child: FloatingActionButton.small(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.7),
          onPressed: () {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutQuart,
            );
          },
          child: const Icon(Icons.timer, color: Colors.white, size: 20),
        ),
      ),

      body: GestureDetector(
        onTap: () { if (_timerFinished) _resetTimer(); },
        child: PIPView(builder: (context, isFloating) => SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            TextField(controller: _workoutTitleController, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), decoration: const InputDecoration(border: InputBorder.none)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.clear_all, color: Colors.orange, size: 32), onPressed: _clearAllSeries, tooltip: 'Limpar caixas'),
              IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 32), onPressed: _addNew, tooltip: 'Novo exercício'),
            ]),
            // --- LINHA DE STATUS DO TREINO ---
            const SizedBox(height: 16),
            const Text('Status do Treino', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: List.generate(_exercises.length, (index) {
                bool isDone = _exercises[index].seriesCompleted.every((c) => c);
                return Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isDone ? Colors.green.withValues(alpha: 0.3) : Colors.transparent,
                    border: Border.all(color: isDone ? Colors.green : Colors.grey.shade600),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: isDone ? const Icon(Icons.check, size: 16, color: Colors.green) : null,
                );
              }),
            ),
            const Divider(height: 32),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _exercises.length,
              onReorder: (oldIdx, newIdx) async {
                setState(() {
                  if (newIdx > oldIdx) newIdx -= 1;
                  final item = _exercises.removeAt(oldIdx);
                  _exercises.insert(newIdx, item);
                });
                await _storage.saveExerciseNames(widget.workoutKey, _exercises.map((e) => e.nameController.text).toList());
              },
              itemBuilder: (context, idx) {
                final ex = _exercises[idx];
                return Card(
                  key: ValueKey('ex_${ex.nameController.text}_$idx'),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: ex.seriesCompleted.every((c) => c) ? Colors.green : Colors.grey.shade400, width: 1)),
                  child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                    TextField(controller: ex.nameController, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), decoration: const InputDecoration(border: InputBorder.none), inputFormatters: [LengthLimitingTextInputFormatter(19)], onChanged: (v) => _saveState(idx)),
                    const SizedBox(height: 8),
                    // CONTROLE DE SÉRIES INDIVIDUAL NO CARD
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(icon: const Icon(Icons.remove_circle_outline, size: 24, color: Colors.grey), onPressed: () { setState(() { ex.updateSeriesCount(ex.repsControllers.length - 1); }); _saveState(idx); }),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                        child: Text('Séries: ${ex.repsControllers.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(icon: const Icon(Icons.add_circle_outline, size: 24, color: Colors.blue), onPressed: () { setState(() { ex.updateSeriesCount(ex.repsControllers.length + 1); }); _saveState(idx); }),
                    ]),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(icon: const Icon(Icons.trending_up, color: Colors.green, size: 24), onPressed: () => _showHistoryChart(ex.nameController.text), tooltip: 'Evolução'),
                      IconButton(icon: const Icon(Icons.ondemand_video, color: Colors.blueGrey, size: 24), onPressed: () => _launchYouTubeSearch(ex.nameController.text), tooltip: 'Tutorial YouTube'),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 24), onPressed: () => _requestRemove(idx)),
                    ]),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (sIdx) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 24, width: 24,
                        child: Checkbox(
                          value: ex.seriesCompleted[sIdx],
                          activeColor: Colors.green,
                          onChanged: (v) {
                            setState(() {
                              ex.seriesCompleted[sIdx] = v ?? false;
                              if (ex.seriesCompleted[sIdx]) {
                                _startTimer(60);
                                final weight = double.tryParse(ex.weightControllers.isNotEmpty ? ex.weightControllers[0].text : '0') ?? 0.0;
                                if (weight > 0) _db.insertHistory(ex.nameController.text, weight);
                              }
                            });
                            _saveState(idx);
                          }
                        ),
                      ),
                    ))),
                    const Divider(height: 24),
                    ...List.generate(ex.repsControllers.length, (sIdx) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CircleAvatar(radius: 10, child: Text('${sIdx + 1}', style: const TextStyle(fontSize: 10))),
                        const SizedBox(width: 12),
                        const Text('Rep:', style: TextStyle(fontSize: 12)),
                        SizedBox(width: 35, child: TextField(controller: ex.repsControllers[sIdx], textAlign: TextAlign.center, style: const TextStyle(fontSize: 14), decoration: const InputDecoration(isDense: true), keyboardType: TextInputType.number, onChanged: (v) => _saveState(idx))),
                        const SizedBox(width: 16),
                        const Text('Peso:', style: TextStyle(fontSize: 12)),
                        SizedBox(width: 45, child: TextField(controller: ex.weightControllers[sIdx], textAlign: TextAlign.center, style: const TextStyle(fontSize: 14), decoration: const InputDecoration(isDense: true, suffixText: 'kg'), keyboardType: TextInputType.number, onChanged: (v) => _saveState(idx))),
                      ]),
                    )),
                  ])),
                );
              },
            ),
            const SizedBox(height: 32),
            // --- CRONÔMETRO EVOLUÍDO ---
            Column(children: [
              const Text('Descanso', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(icon: const Icon(Icons.remove_circle_outline, size: 32), onPressed: () => _adjustTimer(-10)),
                const SizedBox(width: 16),
                Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    height: 110, width: 110,
                    child: CircularProgressIndicator(
                      value: _initialSeconds > 0 ? _remainingSeconds / _initialSeconds : 0,
                      strokeWidth: 8,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      color: _remainingSeconds <= 10 && _remainingSeconds > 0 ? Colors.red : theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  GestureDetector(
                    onTap: _togglePause,
                    onLongPress: _resetTimer,
                    child: ScaleTransition(
                      scale: _pulseAnimation,
                      child: Text(_timerText, style:TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: (_remainingSeconds > 0 && _remainingSeconds <= 10)? Colors.red: theme.textTheme.bodyLarge?.color,)),
                    ),
                  ),
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
          ]),
        )),
      ),
    );
  }
}
