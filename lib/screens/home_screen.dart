import 'package:flutter/material.dart';
import '../main.dart';
import 'workout_screen.dart';
import '../services/storage_service.dart';

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
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _storage.saveLastWorkout('Treino ${String.fromCharCode(65 + _tabController.index)}');
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
