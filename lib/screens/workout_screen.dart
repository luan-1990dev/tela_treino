import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pip_view/pip_view.dart';
import 'package:url_launcher/url_launcher.dart';
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
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
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
        "Como você está se sentindo?\nUm pouco mais cansado (a)?\nNão desista! Todo esforço vai valer a pena.",
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

  Future<void> _loadData() async {
    try {
      if (mounted) setState(() => _isLoading = true);
      final cloudData = await _firestore.getWorkoutFromCloud(widget.workoutKey);
      List<String>? names;
      if (cloudData != null && cloudData.exists) {
        final data = cloudData.data() as Map<String, dynamic>;
        names = List<String>.from(data['names'] ?? []);
      }
      if (names == null || names.isEmpty) names = await _storage.getExerciseNames(widget.workoutKey);
      if (names == null || names.isEmpty) {
        names = ['Supino reto', 'Pec deck', 'Elevação lateral', 'Tríceps polia'];
        await _storage.saveExerciseNames(widget.workoutKey, names);
      }
      final savedTitle = await _storage.getWorkoutTitle(widget.workoutKey);
      if (savedTitle != null) _titleController.text = savedTitle;
      final loaded = <Exercise>[];
      for (int i = 0; i < names.length; i++) {
        final savedCount = await _storage.getSeriesCount(widget.workoutKey, i) ?? 4;
        final reps = await _storage.getRepsList(widget.workoutKey, i);
        final weights = await _storage.getWeightsList(widget.workoutKey, i);
        final notes = await _storage.getExerciseNotes(widget.workoutKey, i) ?? '';
        final times = await _storage.getExerciseTimestamps(widget.workoutKey, i);
        final ex = Exercise(name: names[i], seriesCount: savedCount, initialReps: reps, initialWeights: weights, initialNotes: notes, startTime: times['start'], endTime: times['end']);
        final series = await _storage.getSeriesState(widget.workoutKey, i);
        if (series != null) { ex.seriesCompleted = List.from(series); ex.updateSeriesCount(savedCount); }
        loaded.add(ex);
      }
      if (mounted) setState(() { _exercises = loaded; _isLoading = false; });
    } catch (e) { if (mounted) setState(() { _isLoading = false; }); }
  }

  Future<void> _autoSync() async {
    try {
      final names = _exercises.map((e) => e.nameController.text).toList();
      await _firestore.syncWorkoutToCloud(
        workoutKey: widget.workoutKey, workoutTitle: _titleController.text, names: names,
        seriesStates: {for (var i = 0; i < _exercises.length; i++) i: _exercises[i].seriesCompleted},
        repsLists: {for (var i = 0; i < _exercises.length; i++) i: _exercises[i].repsControllers.map((c) => c.text).toList()},
        weightsLists: {for (var i = 0; i < _exercises.length; i++) i: _exercises[i].weightControllers.map((c) => c.text).toList()},
        notesLists: {for (var i = 0; i < _exercises.length; i++) i: _exercises[i].notesController.text},
      );
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
    await _storage.saveExerciseTimestamps(widget.workoutKey, index, ex.startTime, ex.endTime);
    _autoSync();
    
    int completedExercises = _exercises.where((e) => e.seriesCompleted.every((c) => c)).length;
    if (completedExercises == _exercises.length - 1 && completedExercises > 0 && !_hasShownMotivationalSnackBar) {
      _showMotivationalSnackBar();
      _hasShownMotivationalSnackBar = true;
    }

    if (_exercises.every((e) => e.seriesCompleted.every((c) => c))) {
      _showWorkoutCompleteSnackBar();
    }
  }

  void _showMotivationalSnackBar() {
    final screenHeight = MediaQuery.of(context).size.height;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 5), behavior: SnackBarBehavior.floating, backgroundColor: Colors.orange.shade800, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: EdgeInsets.only(bottom: screenHeight / 2 - 40, left: 30, right: 30),
      content: const Text("Agora falta pouco, só falta mais um treino para a glória eterna! 🏆", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
    ));
  }

  void _showWorkoutCompleteSnackBar() async {
    final currentVolume = _calculateCurrentTotalVolume();
    final previousVolume = await _calculatePreviousTotalVolume();
    final diff = currentVolume - previousVolume;
    Duration totalDuration = Duration.zero;
    for (var ex in _exercises) if (ex.startTime != null && ex.endTime != null) totalDuration += ex.endTime!.difference(ex.startTime!);
    int h = totalDuration.inHours; int m = totalDuration.inMinutes % 60; int s = totalDuration.inSeconds % 60;
    String timeString = h > 0 ? "$h h $m min $s seg" : "$m min $s seg";
    String emoji = diff > 0.5 ? '😁' : (diff < -0.5 ? '😔' : '😐');
    Color statusColor = diff > 0.5 ? Colors.greenAccent : (diff < -0.5 ? Colors.redAccent : Colors.white);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 15), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height / 2 - 80, left: 20, right: 20), backgroundColor: const Color(0xFF0D47A1), 
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 44)), const SizedBox(height: 12),
        const Text('Treino concluído!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)), const SizedBox(height: 8),
        Text('Tempo Total: $timeString', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(diff > 0.5 ? Icons.arrow_upward : (diff < -0.5 ? Icons.arrow_downward : Icons.remove), color: statusColor, size: 24),
          const SizedBox(width: 8), Text('${currentVolume.toStringAsFixed(1)} kg', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: statusColor)),
        ]),
        Text('${diff.abs().toStringAsFixed(1)} kg ${diff > 0.5 ? "aumento" : (diff < -0.5 ? "diminuição" : "mantido")}', style: TextStyle(fontSize: 14, color: statusColor.withOpacity(0.8))), const SizedBox(height: 20),
        const Text('Parabéns pela dedicação! 💪', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white70)),
      ]),
    ));
  }

  double _calculateCurrentTotalVolume() {
    double total = 0;
    for (var ex in _exercises) for (int i = 0; i < ex.weightControllers.length; i++) {
      double reps = double.tryParse(ex.repsControllers[i].text) ?? 0;
      double weight = double.tryParse(ex.weightControllers[i].text) ?? 0;
      total += (reps * weight);
    }
    return total;
  }

  Future<double> _calculatePreviousTotalVolume() async {
    double totalPrev = 0;
    for (var ex in _exercises) {
      final history = await _db.getHistory(ex.nameController.text);
      if (history.length >= 2) totalPrev += ((history[history.length - 2]['weight'] as num).toDouble() * 10 * 4);
    }
    return totalPrev;
  }

  void _scrollToPending() {
    _timerService.stopVibration();
    _stopInactivityMonitor();
    int pendingIndex = -1;
    String? pendingName;
    for (int i = 0; i < _exercises.length; i++) {
      if (!_exercises[i].seriesCompleted.every((c) => c)) {
        pendingIndex = i;
        pendingName = _exercises[i].nameController.text;
        break;
      }
    }
    if (pendingIndex != -1 && pendingIndex == _exercises.length - 1) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Atenção: "$pendingName" possui séries pendentes! 🏋️‍♂️'), backgroundColor: Colors.orange.shade800, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height / 2 - 40, left: 30, right: 30)));
    }
    int targetIdx = pendingIndex != -1 ? pendingIndex : _lastMarkedIndex;
    if (targetIdx != -1) {
      double scrollPos = (targetIdx * 380.0) - (MediaQuery.of(context).size.height / 2) + 190.0;
      _scrollController.animateTo(scrollPos.clamp(0, _scrollController.position.maxScrollExtent), duration: const Duration(milliseconds: 800), curve: Curves.easeInOutQuart);
    }
  }

  void _showSoundSettings() async {
    final currentSound = await _storage.getSelectedSound();
    final soundEnabled = await _storage.getSoundEnabled();
    final vibEnabled = await _storage.getVibrationEnabled();
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Alerta de Descanso', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(title: const Text('Som', style: TextStyle(color: Colors.white70)), value: soundEnabled, activeColor: Colors.blue, onChanged: (v) async { await _storage.saveSoundEnabled(v); setDialogState(() {}); }),
        SwitchListTile(title: const Text('Vibração', style: TextStyle(color: Colors.white70)), value: vibEnabled, activeColor: Colors.blue, onChanged: (v) async { await _storage.saveVibrationEnabled(v); setDialogState(() {}); }),
        const Divider(color: Colors.white12),
        const Text('Tipo de Toque', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
        _soundOption('Bipe Curto', 'Notification', currentSound, setDialogState),
        _soundOption('Alarme Nativo', 'Alarm', currentSound, setDialogState),
        _soundOption('Toque de Vidro', 'Glass', currentSound, setDialogState),
        _soundOption('Campainha', 'Ringtone', currentSound, setDialogState),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('FECHAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))]
    )));
  }

  Widget _soundOption(String label, String value, String current, StateSetter setDialogState) {
    return RadioListTile<String>(
      title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)), value: value, groupValue: current, activeColor: Colors.amber,
      onChanged: (v) async { if (v != null) { await _storage.saveSelectedSound(v); setDialogState(() {}); } },
    );
  }

  void _addNew() {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), title: const Text('Novo Exercício', style: TextStyle(color: Colors.white)), content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Nome do exercício', hintStyle: TextStyle(color: Colors.grey))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), TextButton(onPressed: () async { if (c.text.isNotEmpty) { setState(() { _exercises.add(Exercise(name: c.text, seriesCount: 4)); }); Navigator.pop(ctx); _autoSync(); } }, child: const Text('Adicionar'))]));
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
    final ex = _exercises[index];
    String durationText = '--:--';
    if (ex.startTime != null && ex.endTime != null) durationText = '${ex.endTime!.difference(ex.startTime!).inMinutes}:${(ex.endTime!.difference(ex.startTime!).inSeconds % 60).toString().padLeft(2, '0')}';
    double prevWeight = (history.length >= 2) ? (history[history.length-2]['weight'] as num).toDouble() : (history.first['weight'] as num).toDouble();
    double currentWeight = (history.last['weight'] as num).toDouble();
    double trendWeight = currentWeight + ((currentWeight - prevWeight) > 0 ? (currentWeight - prevWeight) * 0.2 : 2.0);
    if (mounted) {
      showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), title: Center(child: Text('Tendência: $name', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))), content: Container(height: 320, width: double.maxFinite, child: Column(children: [Expanded(child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: FlTitlesData(show: true, leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) { if (val == 0) return const Text('ONTEM', style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)); if (val == 1) return const Text('HOJE', style: TextStyle(color: Colors.blue, fontSize: 9, fontWeight: FontWeight.bold)); if (val == 2) return const Text('META', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold)); return const SizedBox(); }))), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: [FlSpot(0, prevWeight), FlSpot(1, currentWeight), FlSpot(2, trendWeight)], isCurved: true, curveSmoothness: 0.35, color: Colors.blue, barWidth: 5, isStrokeCapRound: true, dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: index == 1 ? Colors.blue : (index == 2 ? Colors.green : Colors.grey), strokeWidth: 2, strokeColor: Colors.white)), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.blue.withOpacity(0.2), Colors.blue.withOpacity(0.0)])))]))), const SizedBox(height: 24), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStat('Tempo Total', durationText), _buildStat('Hoje', '${currentWeight.toStringAsFixed(1)}kg', valueColor: Colors.blue), _buildStat('Projeção', '${trendWeight.toStringAsFixed(1)}kg', valueColor: Colors.green)])])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('VOLTAR', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))]));
    }
  }

  Widget _buildStat(String label, String value, {Color? valueColor}) { return Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)), Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 14, fontWeight: FontWeight.bold))]); }

  Future<void> _launchYouTubeSearch(String exerciseName) async {
    final query = 'Treino em FOCO como fazer ${exerciseName.toLowerCase()}';
    final uri = Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchBenefitsSearch(String exerciseName) async {
    final query = 'Quais os benefícios e como executar o exercício ${exerciseName.toLowerCase()}';
    final uri = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final titleColor = theme.brightness == Brightness.dark ? Colors.white : Colors.black;
    
    return Scaffold(
      floatingActionButton: Stack(children: [
        if (_showTimerButton) Positioned(left: 20, bottom: 16, child: FloatingActionButton.small(onPressed: () => _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut), backgroundColor: Colors.blue.withOpacity(0.6), child: const Icon(Icons.timer, color: Colors.white))),
        if (_timerService.timerFinished) Positioned(right: 20, bottom: 100, child: FloatingActionButton(onPressed: _scrollToPending, backgroundColor: Colors.blue, child: const Icon(Icons.arrow_upward, color: Colors.white))),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: GestureDetector(
        onTap: () { SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); if (_timerService.timerFinished) _timerService.resetTimer(); else _timerService.stopVibration(); },
        child: PIPView(builder: (context, isFloating) => SingleChildScrollView(
          controller: _scrollController, padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.clear_all, color: Colors.orange, size: 32), onPressed: () { setState(() { for (var e in _exercises) { for (var j = 0; j < e.seriesCompleted.length; j++) e.seriesCompleted[j] = false; e.startTime = null; e.endTime = null; } for (int i = 0; i < _exercises.length; i++) _saveState(i); }); }, tooltip: 'Limpar caixas'), 
              IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 32), onPressed: _addNew, tooltip: 'Adicionar exercício'),
              IconButton(icon: const Icon(Icons.music_note, color: Colors.amber, size: 32), onPressed: _showSoundSettings, tooltip: 'Configurações de Alerta'),
            ]),
            const SizedBox(height: 8), Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: TextField(controller: _titleController, textAlign: TextAlign.center, style: TextStyle(color: titleColor, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.5), decoration: const InputDecoration(border: InputBorder.none, hintText: "Nome do Treino"), onChanged: (v) => _saveState(0))),
            const Divider(height: 32),
            ...List.generate(_exercises.length, (idx) {
              final ex = _exercises[idx];
              return Card(key: ValueKey('ex_$idx'), margin: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: ex.seriesCompleted.every((c) => c) ? Colors.green : Colors.grey.shade400)), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                TextField(controller: ex.nameController, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), decoration: const InputDecoration(border: InputBorder.none, hintText: "Exercício"), inputFormatters: [LengthLimitingTextInputFormatter(19)], onChanged: (v) => _saveState(idx)),
                const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(icon: const Icon(Icons.remove_circle_outline, size: 24, color: Colors.grey), onPressed: () { setState(() => ex.updateSeriesCount(ex.seriesCompleted.length - 1)); _saveState(idx); }, tooltip: 'Diminuir séries'), Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)), child: Text('Séries: ${ex.seriesCompleted.length}', style: const TextStyle(fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.add_circle_outline, size: 24, color: Colors.blue), onPressed: () { setState(() => ex.updateSeriesCount(ex.seriesCompleted.length + 1)); _saveState(idx); }, tooltip: 'Aumentar séries')]),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(icon: const Icon(Icons.trending_up, color: Colors.green, size: 24), onPressed: () => _showHistoryChart(ex.nameController.text, idx), tooltip: 'Evolução'),
                  IconButton(icon: const Icon(Icons.ondemand_video, color: Colors.blueGrey, size: 24), onPressed: () => _launchYouTubeSearch(ex.nameController.text), tooltip: 'Tutorial YouTube'),
                  IconButton(icon: const Icon(Icons.info_outline, color: Color(0xFF0D47A1), size: 24), onPressed: () => _launchBenefitsSearch(ex.nameController.text), tooltip: 'Benefícios IA (Google)'),
                  IconButton(icon: Icon(ex.notesController.text.isNotEmpty ? Icons.assignment : Icons.assignment_outlined, color: Colors.amber, size: 24), onPressed: () => _showNotesDialog(idx), tooltip: 'Ver/Editar minhas notas'),
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 24), onPressed: () => _requestRemove(idx), tooltip: 'Excluir exercício'),
                ]),
                const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(ex.seriesCompleted.length, (sIdx) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: SizedBox(height: 24, width: 24, child: Checkbox(value: ex.seriesCompleted[sIdx], activeColor: Colors.green, onChanged: (v) { setState(() { ex.seriesCompleted[sIdx] = v ?? false; _stopInactivityMonitor(); if (v == true) { _lastMarkedIndex = idx; if (ex.startTime == null) ex.startTime = DateTime.now(); if (ex.seriesCompleted.every((c) => c)) ex.endTime = DateTime.now(); } }); _saveState(idx); }))))),
                const Divider(height: 24), ...List.generate(ex.repsControllers.length, (idx2) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircleAvatar(radius: 10, child: Text('${idx2 + 1}', style: const TextStyle(fontSize: 10))), const SizedBox(width: 12), const Text('Rep:'), SizedBox(width: 35, child: TextField(controller: ex.repsControllers[idx2], textAlign: TextAlign.center, decoration: const InputDecoration(isDense: true), keyboardType: TextInputType.number, onChanged: (v) => _saveState(idx))), const SizedBox(width: 16), const Text('Peso:'), SizedBox(width: 55, child: TextField(controller: ex.weightControllers[idx2], textAlign: TextAlign.center, decoration: const InputDecoration(isDense: true, suffixText: 'kg'), keyboardType: TextInputType.number, onChanged: (v) { _db.insertHistory(ex.nameController.text, double.tryParse(v) ?? 0); _saveState(idx); }))])))])));
            }),
            const SizedBox(height: 32), const Text('Descanso', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.remove_circle_outline, size: 32), onPressed: () => _timerService.adjustTimer(-10), tooltip: 'Diminuir 10s'),
              const SizedBox(width: 16),
              Stack(alignment: Alignment.center, children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.withOpacity(0.3), width: 4)), child: SizedBox(height: 110, width: 110, child: CircularProgressIndicator(value: _timerService.initialSeconds > 0 ? _timerService.remainingSeconds / _timerService.initialSeconds : 0, strokeWidth: 8, color: _timerService.remainingSeconds <= 10 && _timerService.remainingSeconds > 0 ? Colors.red : theme.colorScheme.primary))),
                GestureDetector(onTap: () => _timerService.togglePause(), onLongPress: () => _timerService.resetTimer(), child: ScaleTransition(scale: _pulseAnimation, child: Text('${(_timerService.remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_timerService.remainingSeconds % 60).toString().padLeft(2, '0')}', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: _timerService.timerFinished ? (theme.brightness == Brightness.dark ? Colors.white : Colors.black) : ((_timerService.remainingSeconds > 0 && _timerService.remainingSeconds <= 10) ? Colors.red : theme.textTheme.bodyLarge?.color))))),
              ]),
              const SizedBox(width: 16), IconButton(icon: const Icon(Icons.add_circle_outline, size: 32), onPressed: () => _timerService.adjustTimer(10), tooltip: 'Aumentar 10s'),
            ]),
            const SizedBox(height: 24), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [FilledButton(onPressed: () => _timerService.startTimer(45), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade100, foregroundColor: Colors.black), child: const Text('45s')), FilledButton(onPressed: () => _timerService.startTimer(60), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade400), child: const Text('60s')), FilledButton(onPressed: () => _timerService.startTimer(90), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade800), child: const Text('90s')), OutlinedButton(onPressed: () => _timerService.resetTimer(), style: OutlinedButton.styleFrom(foregroundColor: Colors.red), child: const Text('Zerar'))]),
          ]),
        )),
      ),
    );
  }
}
