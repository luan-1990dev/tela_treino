import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../main.dart';
import 'login_screen.dart';
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
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _storage.saveLastWorkout('Treino ${String.fromCharCode(65 + _tabController.index)}');
      }
    });
    _showWelcomeSequence();
  }

  String _getUserName() {
    final email = _auth.currentUser?.email ?? "Atleta";
    return email.split('@')[0].split('.')[0].split('_')[0].toUpperCase();
  }

  // SNACKBAR DE LOGOUT MELHORADA
  void _confirmLogout() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
            const Icon(Icons.exit_to_app_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Deseja sair do app?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'SAIR AGORA',
          textColor: Colors.yellowAccent,
          onPressed: () async {
            try {
              await GoogleSignIn().signOut();
              await _auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            } catch (e) {
              debugPrint("Erro ao sair: $e");
            }
          },
        ),
      ),
    );
  }

  void _showWelcomeSequence() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final lastWelcome = await _storage.getLastWelcomeDate();
      final today = DateTime.now().toIso8601String().split('T')[0];

      if (lastWelcome == today) return;

      final name = _getUserName();
      final screenHeight = MediaQuery.of(context).size.height;
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blue.shade700,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.only(bottom: screenHeight / 2 - 50, left: 20, right: 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, color: Colors.amber, size: 32),
            const SizedBox(height: 8),
            Text("BORA TREINAR, $name!\nFOCO NA EVOLUÇÃO! 💪", textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ));

      await Future.delayed(const Duration(seconds: 4, milliseconds: 500));
      if (!mounted) return;

      final last = await _storage.getLastWorkout();
      if (last != null) {
        int targetIndex = 0;
        if (last.contains('A')) targetIndex = 0;
        else if (last.contains('B')) targetIndex = 1;
        else if (last.contains('C')) targetIndex = 2;
        else if (last.contains('D')) targetIndex = 3;

        setState(() => _tabController.animateTo(targetIndex));

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange.shade800,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.only(bottom: screenHeight / 2 - 50, left: 20, right: 20),
          content: Text('Último treino realizado:\n$last', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ));
        
        await _storage.saveLastWelcomeDate(today);
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
        leading: IconButton(
          icon: Icon(theme.brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: () => themeManager.value = theme.brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
          tooltip: 'Alternar Tema',
        ),
        centerTitle: true,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _confirmLogout,
            tooltip: 'Sair do App',
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
