import 'package:flutter/material.dart';

class Exercise {
  final TextEditingController nameController;
  final TextEditingController seriesCountController;
  List<bool> seriesCompleted;
  List<TextEditingController> repsControllers;
  List<TextEditingController> weightControllers;
  String previousWeight = '';

  // Lista de repetições padrão solicitada
  static const List<String> _defaultRepsProgressive = ['12', '10', '8', '6'];

  Exercise({
    required String name,
    required int seriesCount,
    List<String>? initialReps,
    List<String>? initialWeights,
  })  : nameController = TextEditingController(text: name),
        seriesCountController = TextEditingController(text: seriesCount.toString()),
        seriesCompleted = List.generate(seriesCount, (_) => false),
        repsControllers = List.generate(
          seriesCount,
          (i) {
            String initialValue = '12';
            if (initialReps != null && i < initialReps.length) {
              initialValue = initialReps[i];
            } else if (i < _defaultRepsProgressive.length) {
              // Aplica 12, 10, 8, 6 caso não existam dados salvos
              initialValue = _defaultRepsProgressive[i];
            }
            return TextEditingController(text: initialValue);
          },
        ),
        weightControllers = List.generate(
          seriesCount,
          (i) => TextEditingController(text: (initialWeights != null && i < initialWeights.length) ? initialWeights[i] : ''),
        );

  void updateSeriesCount(int newCount) {
    if (newCount < 1) return;
    if (newCount > seriesCompleted.length) {
      int diff = newCount - seriesCompleted.length;
      seriesCompleted.addAll(List.generate(diff, (_) => false));
      
      // Adiciona novos controladores com os valores padrão se estiverem no range 1-4
      for (int i = repsControllers.length; i < newCount; i++) {
        String defaultValue = (i < _defaultRepsProgressive.length) 
            ? _defaultRepsProgressive[i] 
            : '12';
        repsControllers.add(TextEditingController(text: defaultValue));
        weightControllers.add(TextEditingController(text: ''));
      }
    } else if (newCount < seriesCompleted.length) {
      seriesCompleted = seriesCompleted.sublist(0, newCount);
      repsControllers = repsControllers.sublist(0, newCount);
      weightControllers = weightControllers.sublist(0, newCount);
    }
    seriesCountController.text = newCount.toString();
  }

  void dispose() {
    nameController.dispose();
    seriesCountController.dispose();
    for (var c in repsControllers) c.dispose();
    for (var c in weightControllers) c.dispose();
  }
}
