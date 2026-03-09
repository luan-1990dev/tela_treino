import 'package:flutter/material.dart';

class Exercise {
  final TextEditingController nameController;
  final TextEditingController seriesCountController;
  List<bool> seriesCompleted;
  
  List<TextEditingController> repsControllers;
  List<TextEditingController> weightControllers;
  
  String previousWeight = '';
  bool shouldSuggestIncrease = false;

  Exercise({
    required String name,
    required int seriesCount,
    List<String>? initialReps,
    List<String>? initialWeights,
  })  : nameController = TextEditingController(text: name),
        seriesCountController = TextEditingController(text: seriesCount.toString()),
        seriesCompleted = List.generate(4, (_) => false),
        repsControllers = List.generate(
          seriesCount,
          (i) => TextEditingController(text: (initialReps != null && i < initialReps.length) ? initialReps[i] : '12'),
        ),
        weightControllers = List.generate(
          seriesCount,
          (i) => TextEditingController(text: (initialWeights != null && i < initialWeights.length) ? initialWeights[i] : ''),
        );

  void updateSeriesCount(int newCount) {
    if (newCount < 1 || newCount > 10) return; // Limite de segurança

    // Ajusta a lista de checkboxes
    if (newCount > seriesCompleted.length) {
      seriesCompleted.addAll(List.filled(newCount - seriesCompleted.length, false));
      // Ajusta também os controladores de texto para não dar erro de índice
      for (int i = 0; i < (newCount - repsControllers.length); i++) {
        repsControllers.add(TextEditingController(text: '12'));
        weightControllers.add(TextEditingController(text: ''));
      }
    } else {
      seriesCompleted = seriesCompleted.sublist(0, newCount);
      repsControllers = repsControllers.sublist(0, newCount);
      weightControllers = weightControllers.sublist(0, newCount);
    }
  }

  void dispose() {
    nameController.dispose();
    seriesCountController.dispose();
    for (var c in repsControllers) {
      c.dispose();
    }
    for (var c in weightControllers) {
      c.dispose();
    }
  }
}
