import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class TimerService extends ChangeNotifier {
  // Singleton pattern
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;
  TimerService._internal();

  Timer? _timer;
  Timer? _vibrationTimer;
  
  int _remainingSeconds = 0;
  int _initialSeconds = 0;
  bool _timerFinished = false;
  bool _isPaused = false;

  int get remainingSeconds => _remainingSeconds;
  int get initialSeconds => _initialSeconds;
  bool get timerFinished => _timerFinished;
  bool get isPaused => _isPaused;

  void startTimer(int seconds) {
    stopVibration();
    _timer?.cancel();
    _remainingSeconds = seconds;
    _initialSeconds = seconds;
    _timerFinished = false;
    _isPaused = false;
    
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_isPaused) return;
      
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        _timer?.cancel();
        _timerFinished = true;
        _startAlert(); // Inicia vibração e som simultâneos
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void adjustTimer(int delta) {
    _remainingSeconds = (_remainingSeconds + delta).clamp(0, 999);
    if (_initialSeconds < _remainingSeconds) _initialSeconds = _remainingSeconds;
    
    if ((_timer == null || !_timer!.isActive) && _remainingSeconds > 0) {
      startTimer(_remainingSeconds);
    }
    notifyListeners();
  }

  void togglePause() {
    _isPaused = !_isPaused;
    notifyListeners();
  }

  void resetTimer() {
    stopVibration();
    _timer?.cancel();
    _remainingSeconds = 0;
    _initialSeconds = 0;
    _timerFinished = false;
    _isPaused = false;
    notifyListeners();
  }

  // ALERTA SINCRONIZADO
  void _startAlert() {
    // 1. Inicia o SOM em looping contínuo (Nativo)
    FlutterRingtonePlayer().playAlarm(
      looping: true,
      asAlarm: true,
    );

    // 2. Inicia a VIBRAÇÃO em loop periódico
    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      Vibration.vibrate(pattern: [500, 1000]);
    });
  }

  void stopVibration() {
    _vibrationTimer?.cancel();
    Vibration.cancel();
    FlutterRingtonePlayer().stop(); // Para o som instantaneamente
  }
}
