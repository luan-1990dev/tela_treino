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
    if (newCount < 1) return;
    if (newCount == repsControllers.length) return;

    if (newCount > repsControllers.length) {
      int diff = newCount - repsControllers.length;
      repsControllers.addAll(List.generate(diff, (_) => TextEditingController(text: '12')));
      weightControllers.addAll(List.generate(diff, (_) => TextEditingController()));
    } else {
      for (int i = repsControllers.length - 1; i >= newCount; i--) {
        repsControllers[i].dispose();
        weightControllers[i].dispose();
      }
      repsControllers = repsControllers.sublist(0, newCount);
      weightControllers = weightControllers.sublist(0, newCount);
    }
    seriesCountController.text = newCount.toString();
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
