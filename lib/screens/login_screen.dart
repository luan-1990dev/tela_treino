import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isLoginMode = true;
  bool _obscurePassword = true;
  bool _isEmailValid = true;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_validateEmail);
  }

  void _validateEmail() {
    final email = _emailController.text;
    if (email.isEmpty) {
      setState(() => _isEmailValid = true);
      return;
    }
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    setState(() => _isEmailValid = regex.hasMatch(email));
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // 1. Inicia o processo de seleção de conta
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      
      if (googleUser == null) {
        // Usuário cancelou a seleção
        setState(() => _isLoading = false);
        return;
      }

      // 2. Obtém os detalhes da autenticação
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      // 3. Cria a credencial para o Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Faz o login no Firebase
      await _auth.signInWithCredential(credential);
      
      if (mounted) _goToHome();
    } catch (e) {
      debugPrint("ERRO GOOGLE SIGN IN: $e");
      _showSnackBar('Erro ao entrar com Google. Verifique a chave SHA-1 no Firebase.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty || !_isEmailValid) {
      _showSnackBar('Por favor, preencha os dados corretamente.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLoginMode) {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
      } else {
        await _auth.createUserWithEmailAndPassword(email: email, password: password);
      }
      if (mounted) _goToHome();
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? 'Erro na autenticação.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MyHomePage(title: 'Meu Plano de Treino')),
    );
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !_isEmailValid) {
      _showSnackBar('Digite um e-mail válido para redefinir.');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _showSnackBar('E-mail de redefinição enviado!');
    } catch (e) {
      _showSnackBar('Erro ao enviar e-mail.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/icon/icon.png',
                  height: 140,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.fitness_center, size: 100, color: Colors.blue);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  _isLoginMode ? "" : "CRIAR CONTA",
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                const SizedBox(height: 40),
                
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    "E-mail", 
                    Icons.email_outlined,
                    isError: !_isEmailValid,
                  ),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    "Senha", 
                    Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                
                if (_isLoginMode)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: const Text("Esqueceu a senha?", style: TextStyle(color: Colors.blueAccent, fontSize: 13)),
                    ),
                  ),
                
                const SizedBox(height: 24),
                
                _AnimatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : Text(_isLoginMode ? "ENTRAR" : "CADASTRAR", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                  ),
                ),
                
                const SizedBox(height: 20),
                const Text("OU", style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 20),

                _AnimatedButton(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  child: Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.network('https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png', height: 24),
                        const SizedBox(width: 12),
                        const Text("Entrar com Google", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                
                TextButton(
                  onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                  child: Text(
                    _isLoginMode ? "Não tem uma conta? Cadastre-se" : "Já possui uma conta? Faça login",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {Widget? suffixIcon, bool isError = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: isError ? Colors.redAccent : Colors.grey),
      prefixIcon: Icon(icon, color: isError ? Colors.redAccent : Colors.blue, size: 22),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16), 
        borderSide: isError ? const BorderSide(color: Colors.redAccent, width: 1) : BorderSide.none
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16), 
        borderSide: isError ? const BorderSide(color: Colors.redAccent, width: 1) : const BorderSide(color: Colors.blue, width: 1.5)
      ),
    );
  }
}

class _AnimatedButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  const _AnimatedButton({required this.child, required this.onPressed});

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) => setState(() => _scale = 0.95);
  void _onTapUp(TapUpDetails details) => setState(() => _scale = 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null ? _onTapDown : null,
      onTapUp: widget.onPressed != null ? _onTapUp : null,
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onPressed,
      child: Transform.scale(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
