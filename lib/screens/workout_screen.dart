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
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("App não encontrado ou link inválido.")),
        );
      }
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
      duration: const Duration(seconds: 10),
      backgroundColor: Colors.orange.shade800,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.only(bottom: screenHeight / 2 - 40, left: 30, right: 30),
      content: const Text("Não desista! Todo esforço vale a pena. 💪", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
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

    if (targetIdx != -1 && targetIdx < _exercises.length) {
      double cardHeight = 350.0;
      double screenHeight = MediaQuery.of(context).size.height;
      double scrollPos = (targetIdx * cardHeight) - (screenHeight / 2) + (cardHeight / 2);

      _scrollController.animateTo(
        scrollPos.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeInOutCubic,
      );
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
        final exampleEx = Exercise(
          name: 'Agachamento livre',
          seriesCount: 4,
          initialReps: ['10', '10', '10', '10'],
          initialWeights: ['5', '10', '10', '15'],
          initialNotes: 'Este é um exemplo de exercício.',
        );
        exampleEx.seriesCompleted = [true, true, true, true];
        loadedExercises.add(exampleEx);

        _pulseController.repeat(reverse: true);
        Timer(const Duration(seconds: 15), () {
          if (mounted) _pulseController.stop();
        });
      }

      if (mounted) {
        setState(() {
          _exercises = loadedExercises;
          _isLoading = false;
        });
        _autoSync();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
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

    int m = totalDuration.inMinutes;
    int s = totalDuration.inSeconds % 60;
    String timeString = "${m}m ${s}s";
    String evolutionSign = diff >= 0 ? "+" : "";

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 15),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF0D47A1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.only(bottom: screenHeight / 2 - 120, left: 20, right: 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏆🥇', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text(
            'Treino concluído com sucesso, parabéns pela evolução! 💪',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ));
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 400);
  }

  void _showAlarmSettings() {
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(children: [Icon(Icons.my_library_music, color: Colors.deepPurple, size: 32), SizedBox(width: 10), Text('Ajustes do Alarme', style: TextStyle(color: Colors.white, fontSize: 18))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(title: const Text('Som', style: TextStyle(color: Colors.white70)), value: _timerService.useSound, activeColor: Colors.blue, onChanged: (v) { setState(() => _timerService.setSoundEnabled(v)); setDialogState(() {}); }),
        SwitchListTile(title: const Text('Vibração', style: TextStyle(color: Colors.white70)), value: _timerService.useVibration, activeColor: Colors.orange, onChanged: (v) { setState(() => _timerService.setVibrationEnabled(v)); setDialogState(() {}); }),
        const Divider(color: Colors.white12),
        ListTile(leading: const Icon(Icons.phonelink_setup_rounded, color: Colors.greenAccent), title: const Text('Som do Dispositivo', style: TextStyle(color: Colors.white, fontSize: 14)), onTap: () => _pickCustomSound(setDialogState)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('FECHAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))],
    )));
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
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), title: const Text('Novo Exercício', style: TextStyle(color: Colors.white)), content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Nome do exercício', hintStyle: TextStyle(color: Colors.grey))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), TextButton(onPressed: () async { if (c.text.isNotEmpty) { setState(() { _exercises.add(Exercise(name: c.text, seriesCount: 4)); }); Navigator.pop(ctx); _autoSync(); } }, child: const Text('Adicionar'))]));
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() { if (newIndex > oldIndex) newIndex -= 1; final item = _exercises.removeAt(oldIndex); _exercises.insert(newIndex, item); _manualActiveIndex = -1; });
    _autoSync();
  }

  void _showNotesDialog(int index) {
    final ex = _exercises[index];
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: Text('Notas: ${ex.nameController.text}', style: const TextStyle(color: Colors.white, fontSize: 18)), content: TextField(controller: ex.notesController, maxLines: 3, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Configurações...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))), actions: [TextButton(onPressed: () { _saveState(index); Navigator.pop(ctx); }, child: const Text('SALVAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))]));
  }

  void _showHistoryChart(String name, int index) async {
    final history = await _db.getHistory(name);
    if (history.isEmpty) return;
    final ex = _exercises[index];
    String dur = '--:--';
    if (ex.startTime != null && ex.endTime != null) {
      final diff = ex.endTime!.difference(ex.startTime!);
      dur = "${diff.inMinutes}m ${diff.inSeconds % 60}s";
    }
    double fW = (history.first['weight'] as num).toDouble();
    double cW = double.tryParse(ex.weightControllers.isNotEmpty ? ex.weightControllers.first.text : '0') ?? fW;
    double proj = cW + ((cW - fW) > 0 ? (cW - fW) * 0.2 : 2.0);
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF121212), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), title: Center(child: Text('Tendência: $name', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))), content: Column(mainAxisSize: MainAxisSize.min, children: [SizedBox(height: 180, width: double.maxFinite, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: FlTitlesData(show: true, leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) { if (v == 0) return const Text('INÍCIO', style: TextStyle(color: Colors.grey, fontSize: 10)); if (v == 1) return const Text('HOJE', style: TextStyle(color: Colors.blue, fontSize: 10)); if (v == 2) return const Text('META', style: TextStyle(color: Colors.green, fontSize: 10)); return const SizedBox(); }))), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: [FlSpot(0, fW), FlSpot(1, cW), FlSpot(2, proj)], isCurved: true, color: Colors.blue, barWidth: 5, dotData: const FlDotData(show: true))]))), const SizedBox(height: 20), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStat('Tempo', dur), _buildStat('Evolução', '${(cW - fW).toStringAsFixed(1)}kg'), _buildStat('Hoje', '${cW}kg', valueColor: Colors.blue)])]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('VOLTAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))]));
  }

  Widget _buildStat(String l, String v, {Color? valueColor}) { return Column(children: [Text(l, style: const TextStyle(color: Colors.grey, fontSize: 10)), Text(v, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 14, fontWeight: FontWeight.bold))]); }

  Future<void> _launchBenefitsSearch(String name) async { final url = Uri.parse('https://www.google.com/search?q=benefícios+exercício+${Uri.encodeComponent(name)}'); if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication); }

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
              Positioned(right: 10, bottom: 215.0, child: FloatingActionButton(onPressed: _scrollToPending, backgroundColor: Colors.deepOrange, child: const Icon(Icons.arrow_upward, color: Colors.white))),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () { SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); if (_timerService.timerFinished) _timerService.resetTimer(); else _timerService.stopVibration(); },
        child: PIPView(builder: (context, isFloating) => ReorderableListView.builder(
          scrollController: _scrollController,
          padding: const EdgeInsets.all(12.0),
          itemCount: _exercises.length + 1,
          onReorder: (oldIdx, newIdx) { if (oldIdx >= _exercises.length || newIdx >= _exercises.length) return; _onReorder(oldIdx, newIdx); },
          header: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const FaIcon(FontAwesomeIcons.spotify, color: Color(0xFF1DB954), size: 24), onPressed: () => _launchMusicApp('spotify:')),
              IconButton(icon: const FaIcon(FontAwesomeIcons.youtube, color: Color(0xFFFF0000), size: 24), onPressed: () => _launchMusicApp('youtubemusic:')),
              IconButton(icon: const FaIcon(FontAwesomeIcons.apple, color: Colors.white, size: 24), onPressed: () => _launchMusicApp('music:')),
              IconButton(icon: const FaIcon(FontAwesomeIcons.amazon, color: Color(0xFF00A8E1), size: 24), onPressed: () => _launchMusicApp('amazonmusic:')),
              IconButton(icon: const FaIcon(FontAwesomeIcons.deezer, color: Colors.white, size: 24), onPressed: () => _launchMusicApp('deezer:')),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.clear_all, color: Colors.orange, size: 28), onPressed: () => setState(() { for (var e in _exercises) { for (var j = 0; j < e.seriesCompleted.length; j++) e.seriesCompleted[j] = false; } _autoSync(); }),tooltip: 'Limpar progresso do treino',),
              IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 28), onPressed: (){_addNew();}, tooltip: 'Adicionar novo exercício',),
              IconButton(icon: const Icon(Icons.my_library_music, color: Colors.deepPurple, size: 28), onPressed: _showAlarmSettings,tooltip: 'Ajustes de som e alarme',),
              IconButton(icon: const Icon(Icons.analytics_outlined, color: Colors.greenAccent, size: 28), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => SummaryScreen(exercises: _exercises))); }, tooltip: 'Resumo do Treino'),

            ]),
            TextField(controller: _titleController, textAlign: TextAlign.center, style: TextStyle(color: titleColor, fontSize: 24, fontWeight: FontWeight.bold), decoration: const InputDecoration(border: InputBorder.none), onChanged: (v) => _autoSync()),
            const Divider(height: 32),
          ]),
          itemBuilder: (context, idx) {
            if (idx == _exercises.length) {
              return Column(
                key: const ValueKey('timer_footer'),
                children: [
                  const SizedBox(height: 32),
                  const Text('Cronômetro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 25)),
                  const SizedBox(height: 4),
                  SizedBox(width: 250, child: TextField(controller: _restTitleController, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey), decoration: const InputDecoration(hintText: 'Nome do descanso', border: InputBorder.none, isDense: true), onChanged: (v) => _autoSync())),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _buildTimeButton('45s', 45, Colors.blue.shade100, Colors.black),
                    _buildTimeButton('60s', 60, Colors.blue.shade400, Colors.white),
                    _buildTimeButton('90s', 90, Colors.blue.shade800, Colors.white),
                  ]),
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
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CardioScreen(workoutKey: widget.workoutKey))),
                    child: Column(children: [
                      Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: Colors.green, width: 2.5), boxShadow: theme.brightness == Brightness.light ? [const BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))] : []), child: const Icon(Icons.directions_run_rounded, size: 38, color: Colors.green)),
                      const SizedBox(height: 8),
                      Text('CARDIO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                    ]),
                  ),
                  const SizedBox(height: 120),
                ],
              );
            }

            final ex = _exercises[idx];
            final bool isActive = idx == activeIdx;
            return Card(
              key: ValueKey('ex_$idx'),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              color: isActive ? Colors.blue.withValues(alpha: 0.08) : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isActive ? Colors.deepOrange : (ex.seriesCompleted.every((c) => c) ? Colors.green : Colors.grey.shade400), width: isActive ? 3.5 : 2.0)),
              child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Opacity(opacity: isActive ? 1.0 : 0.0, child: const Icon(Icons.double_arrow_outlined, color: Colors.deepOrange, size: 25)),
                    const SizedBox(height: 4),
                    GestureDetector(onTap: () { setState(() => _manualActiveIndex = idx); _timerService.stopVibration(); }, child: Icon(isActive ? Icons.gps_fixed : Icons.gps_not_fixed, color: isActive ? Colors.deepOrange : Colors.grey.withValues(alpha: 0.5), size: 20)),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: ex.nameController, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isActive ? Colors.deepOrange : null), decoration: const InputDecoration(border: InputBorder.none), onChanged: (v) => _saveState(idx))),
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
                  IconButton(icon: const Icon(Icons.info_outline, color: Colors.blue), onPressed: () => _launchBenefitsSearch(ex.nameController.text)),
                  IconButton(icon: Icon(ex.notesController.text.isNotEmpty ? Icons.assignment : Icons.assignment_outlined, color: Colors.amber), onPressed: () => _showNotesDialog(idx)),
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() { _exercises.removeAt(idx); _autoSync(); })),
                ]),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: Wrap(alignment: WrapAlignment.center, spacing: 0, runSpacing: 0, children: List.generate(ex.seriesCompleted.length, (sIdx) { return Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Checkbox(visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, value: ex.seriesCompleted[sIdx], activeColor: Colors.green, onChanged: (v) { setState(() { ex.seriesCompleted[sIdx] = v ?? false; if (v == true) { _lastMarkedIndex = idx; _manualActiveIndex = idx; _timerService.stopVibration(); bool isFirstMarked = ex.seriesCompleted.where((c) => c).length == 1; if (isFirstMarked) { ex.startTime = DateTime.now(); ex.endTime = null; } if (ex.seriesCompleted.every((c) => c)) ex.endTime = DateTime.now(); } _stopInactivityMonitor(); }); _saveState(idx); })); }))),
                const Divider(),
                ...List.generate(ex.repsControllers.length, (idx2) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Rep:'), SizedBox(width: 40, child: TextField(controller: ex.repsControllers[idx2], textAlign: TextAlign.center, keyboardType: TextInputType.number, onChanged: (v) => _saveState(idx))),
                  const SizedBox(width: 15),
                  const Text('Peso:'),
                  SizedBox(width: 65, child: TextField(controller: ex.weightControllers[idx2], textAlign: TextAlign.center, decoration: const InputDecoration(suffixText: 'kg', isDense: true), keyboardType: TextInputType.number, onChanged: (v) { _db.insertHistory(ex.nameController.text, double.tryParse(v) ?? 0); _saveState(idx); })),
                ])),
              ])),
            );
          },
        )),
      ),
    );
  }

  Widget _buildTimeButton(String label, int seconds, Color bg, Color fg) {
    return FilledButton(onPressed: () => _timerService.startTimer(seconds), style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg, shape: const StadiumBorder()), child: Text(label));
  }
}
