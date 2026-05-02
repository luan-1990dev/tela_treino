import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:audioplayers/audioplayers.dart'; 
import 'storage_service.dart';

class TimerService extends ChangeNotifier {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;

  TimerService._internal() {
    _loadSettings();
    _configureAudioDucking();
  }

  final StorageService _storage = StorageService();
  Timer? _timer;
  Timer? _vibrationTimer;

  int _remainingSeconds = 0;
  int _initialSeconds = 0;
  bool _timerFinished = false;
  bool _isPaused = false;

  bool _useSound = true;
  bool _useVibration = true;
  String _selectedSoundType = 'Notification';

  int get remainingSeconds => _remainingSeconds;
  int get initialSeconds => _initialSeconds;
  bool get timerFinished => _timerFinished;
  bool get isPaused => _isPaused;
  bool get useSound => _useSound;
  bool get useVibration => _useVibration;
  String get selectedSoundType => _selectedSoundType;

  void _configureAudioDucking() {
    AudioPlayer.global.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: const AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        options: [AVAudioSessionOptions.duckOthers],
      ),
    ));
  }

  void setSoundEnabled(bool value) {
    _useSound = value;
    _storage.saveSoundEnabled(value);
    notifyListeners();
  }

  void setVibrationEnabled(bool value) {
    _useVibration = value;
    _storage.saveVibrationEnabled(value);
    notifyListeners();
  }

  void setSelectedSound(String value) {
    _selectedSoundType = value;
    _storage.saveSelectedSound(value);
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    _useSound = await _storage.getSoundEnabled();
    _useVibration = await _storage.getVibrationEnabled();
    _selectedSoundType = await _storage.getSelectedSound();
    notifyListeners();
  }

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
        _startAlert();
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void adjustTimer(int delta) {
    _remainingSeconds = (_remainingSeconds + delta).clamp(0, 999);
    if (_initialSeconds < _remainingSeconds) _initialSeconds = _remainingSeconds;
    if ((_timer == null || !_timer!.isActive) && _remainingSeconds > 0) startTimer(_remainingSeconds);
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

  void _startAlert() {
    if (_useSound) {
      if (_selectedSoundType == 'Alarm') {
        FlutterRingtonePlayer().playAlarm(looping: true, asAlarm: false);
      } else if (_selectedSoundType == 'Ringtone') {
        FlutterRingtonePlayer().playRingtone(looping: true, asAlarm: false);
      } else if (_selectedSoundType == 'Glass') {
        FlutterRingtonePlayer().play(android: AndroidSounds.notification, ios: IosSounds.glass, looping: true, asAlarm: false);
      } else {
        FlutterRingtonePlayer().play(android: AndroidSounds.notification, ios: IosSounds.triTone, looping: true, asAlarm: false);
      }
    }

    if (_useVibration) {
      _vibrationTimer?.cancel();
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (t) {
        Vibration.vibrate(pattern: [500, 1000]);
      });
    }
  }

  void stopVibration() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    Vibration.cancel();
    FlutterRingtonePlayer().stop();
  }
}
