import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tela_treino/screens/home_screen.dart';
import 'package:tela_treino/screens/login_screen.dart';

// Gerenciador de tema global
final themeManager = ValueNotifier<ThemeMode>(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp();
    firebaseInitialized = true;
  } catch (e) {
    debugPrint("Erro ao inicializar Firebase: $e");
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  runApp(MyApp(isFirebaseReady: firebaseInitialized));
}

class MyApp extends StatelessWidget {
  final bool isFirebaseReady;
  const MyApp({super.key, required this.isFirebaseReady});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeManager,
      builder: (context, currentMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'App de Treino Pro',
          theme: ThemeData(colorSchemeSeed: Colors.blue, brightness: Brightness.light, useMaterial3: true),
          darkTheme: ThemeData(colorSchemeSeed: Colors.blue, brightness: Brightness.dark, useMaterial3: true),
          themeMode: currentMode,
          home: !isFirebaseReady 
            ? const FirebaseErrorScreen() 
            : StreamBuilder<User?>(
                stream: FirebaseAuth.instance.authStateChanges(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(body: Center(child: CircularProgressIndicator()));
                  }
                  if (snapshot.hasData) {
                    return const MyHomePage(title: 'Meu Plano de Treino');
                  }
                  return const LoginScreen();
                },
              ),
        );
      },
    );
  }
}

class FirebaseErrorScreen extends StatelessWidget {
  const FirebaseErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon/icon.png',
                height: 100,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.error_outline, color: Colors.red, size: 80),
              ),
              const SizedBox(height: 24),
              const Text(
                "Configuração Pendente",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                "O Firebase não foi detectado. Certifique-se de adicionou o arquivo 'google-services.json' na pasta android/app.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text("SAIR E CONFIGURAR"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
