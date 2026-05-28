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

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !_isEmailValid) {
      _showSnackBar('Insira um e-mail válido para recuperar a senha.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _showSnackBar('E-mail de recuperação enviado! Verifique sua caixa de entrada.', isError: false);
    } catch (e) {
      _showSnackBar('Erro ao solicitar recuperação: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
      if (mounted) _goToHome();
    } catch (e) {
      debugPrint("ERRO GOOGLE: $e");
      String errorMsg = 'Falha no login com Google.';
      if (e.toString().contains('400')) errorMsg = 'Erro de requisição (400). Verifique sua conexão.';
      if (e.toString().contains('429')) errorMsg = 'Muitas tentativas. Aguarde um pouco.';
      _showSnackBar(errorMsg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty || !_isEmailValid) {
      _showSnackBar('Preencha os dados corretamente.');
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

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, textAlign: TextAlign.center),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? Colors.red : Colors.green,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView( // EVITA OVERFLOW QUANDO O TECLADO SOBE
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                    'assets/icon/icon.png',
                    height: 140,
                    errorBuilder: (ctx, e, st) => const Icon(Icons.fitness_center, size: 100, color: Colors.blue)
                ),
                const SizedBox(height: 40),

                // Campo E-mail
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration("E-mail", Icons.email_outlined, isError: !_isEmailValid),
                ),
                const SizedBox(height: 16),

                // Campo Senha
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                      "Senha",
                      Icons.lock_outline,
                      suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword)
                      )
                  ),
                ),

                // LINK ESQUECEU A SENHA (RECUPERAR)
                if (_isLoginMode)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _resetPassword,
                      child: const Text('Esqueceu a senha?', style: TextStyle(color: Colors.blue, fontSize: 13)),
                    ),
                  ),

                const SizedBox(height: 16),

                // Botão Principal (Entrar/Cadastrar)
                _AnimatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: Container(
                    width: double.infinity, height: 55,
                    decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(_isLoginMode ? "ENTRAR" : "CADASTRAR", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 20),
                const Text("OU", style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 20),

                // Botão Google (AJUSTADO PARA OVERFLOW)
                _AnimatedButton(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  child: Container(
                    width: double.infinity,
                    height: 55,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16)
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Flexible(
                            child: Text(
                                "Continuar com Google",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold
                                )
                            )
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Toggle Login/Cadastro
                TextButton(
                    onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                    child: Text(
                        _isLoginMode ? "Não tem uma conta? Cadastre-se" : "Já possui uma conta? Faça login",
                        style: const TextStyle(color: Colors.grey)
                    )
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
      fillColor: Colors.white.withOpacity(0.05),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: isError ? const BorderSide(color: Colors.redAccent, width: 1) : BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: isError ? const BorderSide(color: Colors.redAccent, width: 1) : const BorderSide(color: Colors.blue, width: 1.5)),
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
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) => setState(() => _scale = 0.95),
      onTapUp: (d) => setState(() => _scale = 1.0),
      onTap: widget.onPressed,
      child: Transform.scale(scale: _scale, child: widget.child),
    );
  }
}
