import 'package:flutter/material.dart';

class Exercise {
  final TextEditingController nameController;
  final TextEditingController seriesCountController;
  final TextEditingController notesController;
  List<bool> seriesCompleted;
  List<TextEditingController> repsControllers;
  List<TextEditingController> weightControllers;
  String previousWeight = '';

  // Timestamps para cálculo de duração do exercício
  DateTime? startTime;
  DateTime? endTime;

  static const List<String> _defaultRepsProgressive = ['12', '10', '8', '6'];

  Exercise({
    required String name,
    required int seriesCount,
    List<String>? initialReps,
    List<String>? initialWeights,
    String initialNotes = '',
    this.startTime,
    this.endTime,
  })  : nameController = TextEditingController(text: name),
        seriesCountController = TextEditingController(text: seriesCount.toString()),
        notesController = TextEditingController(text: initialNotes),
        seriesCompleted = List.generate(seriesCount, (_) => false),
        repsControllers = List.generate(
          seriesCount,
          (i) {
            String initialValue = '12';
            if (initialReps != null && i < initialReps.length) {
              initialValue = initialReps[i];
            } else if (i < _defaultRepsProgressive.length) {
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
      for (int i = repsControllers.length; i < newCount; i++) {
        String defaultValue = (i < _defaultRepsProgressive.length) 
            ? _defaultRepsProgressive[i] 
            : '12';
        repsControllers.add(TextEditingController(text: defaultValue));
        weightControllers.add(TextEditingController(text: ''));
      }
    } else {
      seriesCompleted = seriesCompleted.sublist(0, newCount);
      repsControllers = repsControllers.sublist(0, newCount);
      weightControllers = weightControllers.sublist(0, newCount);
    }
    seriesCountController.text = newCount.toString();
  }

  void dispose() {
    nameController.dispose();
    seriesCountController.dispose();
    notesController.dispose();
    for (var c in repsControllers) {
      c.dispose();
    }
    for (var c in weightControllers) {
      c.dispose();
    }
  }
}
