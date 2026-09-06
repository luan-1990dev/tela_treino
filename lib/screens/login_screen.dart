import 'dart:async';
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
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isLoginMode = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
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

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty || !_isEmailValid) {
      _showSnackBar('Preencha os dados corretamente.');
      return;
    }

    if (!_isLoginMode && password != confirmPassword) {
      _showSnackBar('As senhas não coincidem!');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
      } else {
        await _auth.createUserWithEmailAndPassword(email: email, password: password);
        await _auth.currentUser?.updateDisplayName(_nameController.text);
      }
      if (mounted) _goToHome();
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? 'Erro na autenticação.');
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
      _showSnackBar('Falha no login com Google.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !_isEmailValid) {
      _showSnackBar('Insira um e-mail válido.', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _showSnackBar('E-mail de recuperação enviado!', isError: false);
    } catch (e) {
      _showSnackBar('Erro ao solicitar recuperação.', isError: true);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // BOTÃO DE VOLTAR NA APPBAR (Apenas no modo cadastro)
      appBar: !_isLoginMode
          ? AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _isLoginMode = true),
        ),
      )
          : null,
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
                // LOGO: Só aparece no modo Login
                if (_isLoginMode)
                  Container(
                    height: 140,
                    margin: const EdgeInsets.only(bottom: 40),
                    decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 40, spreadRadius: 5)],
                    ),
                    child: Image.asset('assets/icon/icon.png',
                        errorBuilder: (ctx, e, st) => const Icon(Icons.fitness_center, size: 100, color: Colors.blue)
                    ),
                  ),

                // 1. CAMPO NOME (Apenas Cadastro)
                if (!_isLoginMode) ...[
                  _buildTextField(
                    controller: _nameController,
                    hint: "Nome Completo",
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                ],

                // 2. CAMPO E-MAIL
                _buildTextField(
                  controller: _emailController,
                  hint: "E-mail",
                  icon: Icons.email_outlined,
                  isError: !_isEmailValid,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                // 3. CAMPO SENHA
                _buildTextField(
                  controller: _passwordController,
                  hint: "Senha",
                  icon: Icons.lock_outline,
                  obscure: _obscurePassword,
                  suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword)
                  ),
                ),

                // 4. CAMPO CONFIRMAR SENHA (Apenas Cadastro)
                if (!_isLoginMode) ...[
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _confirmPasswordController,
                    hint: "Confirmar Senha",
                    icon: Icons.password_outlined,
                    obscure: _obscureConfirmPassword,
                    suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword)
                    ),
                  ),
                ],

                // ESQUECEU A SENHA (Só Login)
                if (_isLoginMode)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _resetPassword,
                      child: const Text('Esqueceu a senha?', style: TextStyle(color: Colors.blue, fontSize: 13)),
                    ),
                  ),

                const SizedBox(height: 24),

                // BOTÃO PRINCIPAL (Entrar ou Cadastrar)
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

                // DIVISOR E GOOGLE: Só aparecem no modo Login
                if (_isLoginMode) ...[
                  const SizedBox(height: 20),
                  const Text("OU", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 20),
                  _AnimatedButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    child: Container(
                      width: double.infinity,
                      height: 55,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text("G", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
                          SizedBox(width: 12),
                          Text("Continuar com Google", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // LINK PARA ALTERNAR: Só aparece no modo Login
                if (_isLoginMode)
                  TextButton(
                      onPressed: () => setState(() {
                        _isLoginMode = false;
                        _emailController.clear();
                        _passwordController.clear();
                      }),
                      child: const Text(
                          "Não tem uma conta? Cadastre-se",
                          style: TextStyle(color: Colors.grey)
                      )
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool isError = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        prefixIcon: Icon(icon, color: isError ? Colors.redAccent : Colors.blueAccent, size: 22),
        suffixIcon: suffixIcon,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: isError ? const BorderSide(color: Colors.redAccent, width: 1) : BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.blue, width: 1.5)),
      ),
    );
  }
}

class _AnimatedButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  const _AnimatedButton({required this.child, required this.onPressed, super.key});
  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onPressed,
      child: Transform.scale(scale: _scale, child: widget.child),
    );
  }
}
