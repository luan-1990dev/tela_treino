import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CardioScreen extends StatefulWidget {
  final String workoutKey;
  const CardioScreen({super.key, required this.workoutKey});

  @override
  State<CardioScreen> createState() => _CardioScreenState();
}

class _CardioScreenState extends State<CardioScreen> {
  final _minutosController = TextEditingController();
  final _velocidadeController = TextEditingController();
  double _calorias = 0;

  // --- NOVA FUNÇÃO DE COMPARAÇÃO ---
  String _getComparacaoAlimento(double kcal) {
    if (kcal <= 0) return "";
    if (kcal < 50) return "Equivale a um punhado de morangos 🍓";
    if (kcal < 120) return "Equivale a uma maçã 🍎";
    if (kcal < 200) return "Equivale a uma latinha de refrigerante 🥤";
    if (kcal < 300) return "Equivale a um pão francês com manteiga 🥖";
    if (kcal < 450) return "Equivale a uma fatia de pizza 🍕";
    if (kcal < 600) return "Equivale a um hambúrguer clássico 🍔";
    if (kcal < 800) return "Equivale a um pedaço grande de bolo de chocolate 🍰";
    return "Equivale a uma refeição completa! 🍲";
  }

  void _calcularCalorias() {
    double min = double.tryParse(_minutosController.text) ?? 0;
    double vel = double.tryParse(_velocidadeController.text) ?? 0;

    setState(() {
      // Fórmula simplificada: (Velocidade * MET) * Peso(70kg) * Tempo
      _calorias = (vel * 0.75) * 70 * (min / 60);
    });
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
      'minutos': double.parse(_minutosController.text),
      'velocidade': double.parse(_velocidadeController.text),
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
        title: const Text('Esteira / Cardio', style: TextStyle(fontSize: 18)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInputCard(),
            const SizedBox(height: 25),
            _buildHistoryCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Card(
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minutosController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                    onChanged: (_) => _calcularCalorias(),
                    decoration: InputDecoration(
                      labelText: 'Minutos',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.timer, color: Colors.lightGreenAccent),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: TextField(
                    controller: _velocidadeController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                    onChanged: (_) => _calcularCalorias(),
                    decoration: InputDecoration(
                      labelText: 'Vel. km/h',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.speed, color: Colors.lightGreenAccent),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 35),
            Text(
              '${_calorias.toStringAsFixed(0)} kcal',
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: Colors.lightGreenAccent),
            ),
            const Text('GASTO ESTIMADO', style: TextStyle(color: Colors.white54, letterSpacing: 1.5, fontSize: 12)),

            // --- EXIBIÇÃO DA CURIOSIDADE ---
            if (_calorias > 0) ...[
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.lightGreenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getComparacaoAlimento(_calorias),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.green, fontSize: 20, fontStyle: FontStyle.italic),
                ),
              ),
            ],

            const SizedBox(height: 35),
            ElevatedButton(
              onPressed: _salvarCardio,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightGreenAccent,
                  minimumSize: const Size(double.maxFinite, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0
              ),
              child: const Text('SALVAR SESSÃO', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),
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
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.lightGreenAccent));

        double totalMes = 0;
        double totalSemana = 0;
        final hoje = DateTime.now();
        final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          double cal = (data['calorias'] as num).toDouble();
          totalMes += cal;

          DateTime dataDoc = (data['timestamp'] as Timestamp).toDate();
          if (dataDoc.isAfter(inicioSemana)) {
            totalSemana += cal;
          }
        }

        return Container(
          padding: const EdgeInsets.all(24),
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
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
        const Text('kcal', style: TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
      ],
    );
  }
}