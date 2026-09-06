import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

enum CardioType { esteira, bike, escada }

class CardioScreen extends StatefulWidget {
  final String workoutKey;
  const CardioScreen({super.key, required this.workoutKey});

  @override
  State<CardioScreen> createState() => _CardioScreenState();
}

class _CardioScreenState extends State<CardioScreen> {
  CardioType _selectedType = CardioType.esteira;
  final _minutosController = TextEditingController();
  final _velocidadeController = TextEditingController();
  double _calorias = 0;

  // Lógica de cálculo baseada em MET (Equivalente Metabólico)
  void _calcularCalorias() {
    double min = double.tryParse(_minutosController.text) ?? 0;
    double vel = double.tryParse(_velocidadeController.text) ?? 0;
    double met = 0;

    switch (_selectedType) {
      case CardioType.esteira:
        met = vel * 1.1;
        break;
      case CardioType.bike:
        met = vel * 0.7;
        break;
      case CardioType.escada:
        met = vel * 1.4;
        break;
    }

    setState(() {
      _calorias = (met * 3.5 * 75 / 200) * min;
    });
  }

  String _getComparacaoAlimento(double kcal) {
    if (kcal <= 0) return "";
    if (kcal < 50) return "Equivale a um punhado de morangos 🍓";
    if (kcal < 120) return "Equivale a uma maçã 🍎";
    if (kcal < 200) return "Equivale a uma latinha de refrigerante 🥤";
    if (kcal < 300) return "Equivale a um pão francês com manteiga 🥖";
    if (kcal < 450) return "Equivale a uma fatia de pizza 🍕";
    if (kcal < 650) return "Equivale a um hambúrguer clássico 🍔"; // Ajustado de 600
    if (kcal < 900) return "Equivale a um pedaço de bolo de chocolate 🍰"; // Ajustado de 800
    return "Equivale a uma refeição completa! 🍲";
  }

  Future<void> _salvarCardio() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _calorias <= 0) return;

    final agora = DateTime.now();
    final mesReferencia = DateFormat('MM/yyyy').format(agora);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('cardio')
        .add({
      'timestamp': agora,
      'tipo': _selectedType.name,
      'minutos': double.parse(_minutosController.text),
      'intensidade': double.parse(_velocidadeController.text),
      'calorias': _calorias,
      'mes_referencia': mesReferencia,
    });

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        // CORREÇÃO: Título removido, mantendo apenas a seta
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. SELETOR DE MODALIDADE
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // CORREÇÃO: Novo ícone para Esteira (directions_walk)
                _buildTypeButton(CardioType.esteira, Icons.monitor_heart_rounded, 'Esteira'),
                _buildTypeButton(CardioType.bike, Icons.directions_bike_rounded, 'Bike'),
                _buildTypeButton(CardioType.escada, Icons.stairs_rounded, 'Escada'),
              ],
            ),
            const SizedBox(height: 25),

            // 2. CARD DE INPUTS
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  _buildAnimatedIcon(),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      Expanded(child: _buildInput(_minutosController, 'Minutos', Icons.timer)),
                      const SizedBox(width: 15),
                      Expanded(child: _buildInput(_velocidadeController, _selectedType == CardioType.escada ? 'Nível' : 'km/h', Icons.speed)),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Text(
                    '${_calorias.toStringAsFixed(0)} kcal',
                    style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: Colors.lightGreenAccent),
                  ),
                  const Text('GASTO ESTIMADO', style: TextStyle(color: Colors.white38, letterSpacing: 1.5, fontSize: 10)),

                  if (_calorias > 0) ...[
                    const SizedBox(height: 15),
                    Text(
                      _getComparacaoAlimento(_calorias),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.lightGreenAccent, fontStyle: FontStyle.italic, fontSize: 14),
                    ),
                  ]
                ],
              ),
            ),

            const SizedBox(height: 25),

            // 3. ESTATÍSTICAS (SEMANA/MÊS)
            _buildHistoryCard(),

            const SizedBox(height: 25),

            ElevatedButton(
              onPressed: _salvarCardio,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightGreenAccent,
                minimumSize: const Size(double.maxFinite, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('SALVAR SESSÃO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton(CardioType type, IconData icon, String label) {
    bool isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() { _selectedType = type; _calcularCalorias(); }),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.lightGreenAccent : Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isSelected ? Colors.black : Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: isSelected ? Colors.lightGreenAccent : Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white, fontSize: 18),
      onChanged: (_) => _calcularCalorias(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.lightGreenAccent, size: 20),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildAnimatedIcon() {
    IconData icon;
    switch (_selectedType) {
    // CORREÇÃO: Ícone alterado no switch da animação também
      case CardioType.esteira: icon = Icons.monitor_heart_sharp; break;
      case CardioType.bike: icon = Icons.directions_bike_rounded; break;
      case CardioType.escada: icon = Icons.stairs_rounded; break;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: RunningCardioIcon(key: ValueKey(_selectedType), icon: icon),
    );
  }

  Widget _buildHistoryCard() {
    final user = FirebaseAuth.instance.currentUser;
    final mesAtual = DateFormat('MM/yyyy').format(DateTime.now());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .collection('cardio')
          .where('mes_referencia', isEqualTo: mesAtual)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        double totalMes = 0;
        double totalSemana = 0;
        final hoje = DateTime.now();
        final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          double cal = (data['calorias'] as num).toDouble();
          totalMes += cal;
          DateTime dataDoc = (data['timestamp'] as Timestamp).toDate();
          if (dataDoc.isAfter(inicioSemana)) totalSemana += cal;
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('NA SEMANA', totalSemana),
              Container(width: 1, height: 40, color: Colors.white10),
              _buildStatItem('NO MÊS', totalMes),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        const Text('kcal', style: TextStyle(color: Colors.lightGreenAccent, fontSize: 10)),
      ],
    );
  }
}

class RunningCardioIcon extends StatefulWidget {
  final IconData icon;
  const RunningCardioIcon({required this.icon, super.key});

  @override
  State<RunningCardioIcon> createState() => _RunningCardioIconState();
}

class _RunningCardioIconState extends State<RunningCardioIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this)..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0, end: -10).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _bounce.value),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.lightGreenAccent.withOpacity(0.5), width: 2),
              boxShadow: [
                BoxShadow(
                    color: Colors.lightGreenAccent.withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: _controller.value * 10
                )
              ],
            ),
            child: Icon(widget.icon, size: 45, color: Colors.lightGreenAccent),
          ),
        );
      },
    );
  }
}