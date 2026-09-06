import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart'; // Importação necessária
import 'storage_service.dart';

class TimerService extends ChangeNotifier {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;

  TimerService._internal() {
    _loadSettings();
    _configureAudioDucking();
    _restoreRunningTimer();
  }

  final StorageService _storage = StorageService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _timer;

  int _remainingSeconds = 0;
  int _initialSeconds = 0;
  bool _timerFinished = false;
  bool _isPaused = false;
  DateTime? _targetEndTime;

  bool _useSound = true;
  bool _useVibration = true;
  String _selectedSoundType = 'Notification';
  String? _customSoundPath;

  // Getters
  int get remainingSeconds => _remainingSeconds;
  int get initialSeconds => _initialSeconds;
  bool get timerFinished => _timerFinished;
  bool get isPaused => _isPaused;
  bool get useSound => _useSound;
  bool get useVibration => _useVibration;
  String get selectedSoundType => _selectedSoundType;

  String get timerText => '${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}';

  void _configureAudioDucking() {
    AudioPlayer.global.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: const AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: [AVAudioSessionOptions.duckOthers],
      ),
    ));
  }

  // --- LÓGICA DE SOM ATUALIZADA (NATIVO + CUSTOM) ---
  void _playAlarmSound() async {
    if (!_useSound) return;

    try {
      if (_selectedSoundType == 'Custom' && _customSoundPath != null) {
        // Toca arquivo personalizado do usuário
        await _audioPlayer.play(DeviceFileSource(_customSoundPath!));
      } else if (_selectedSoundType == 'Alarm') {
        FlutterRingtonePlayer().playAlarm(volume: 0.8, looping: false);
      } else if (_selectedSoundType == 'Notification') {
        FlutterRingtonePlayer().playNotification(volume: 0.8);
      } else if (_selectedSoundType == 'Ringtone') {
        FlutterRingtonePlayer().playRingtone(volume: 0.8, looping: false);
      } else {
        // Fallback: Toca o som de alarme padrão do asset
        await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
      }
    } catch (e) {
      debugPrint("Erro ao tocar som: $e");
    }
  }

  Future<void> _restoreRunningTimer() async {
    final savedTarget = await _storage.getTimerTargetTime();
    if (savedTarget != null) {
      final now = DateTime.now();
      if (savedTarget.isAfter(now)) {
        _targetEndTime = savedTarget;
        _initialSeconds = await _storage.getTimerInitialSeconds() ?? 60;
        _timerFinished = false;
        _isPaused = false;
        _startCountdownLogic();
      } else {
        _storage.clearTimerData();
      }
    }
  }

  Future<void> _loadSettings() async {
    _useSound = await _storage.getSoundEnabled();
    _useVibration = await _storage.getVibrationEnabled();
    _selectedSoundType = await _storage.getSelectedSound();
    _customSoundPath = await _storage.getCustomSoundPath();
    notifyListeners();
  }

  void startTimer(int seconds) {
    stopVibration();
    _timer?.cancel();
    _initialSeconds = seconds;
    _remainingSeconds = seconds;
    _timerFinished = false;
    _isPaused = false;
    _targetEndTime = DateTime.now().add(Duration(seconds: seconds));
    _storage.saveTimerTargetTime(_targetEndTime!);
    _storage.saveTimerInitialSeconds(seconds);
    _startCountdownLogic();
  }

  void _startCountdownLogic() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (_isPaused || _targetEndTime == null) return;
      final now = DateTime.now();
      final difference = _targetEndTime!.difference(now).inSeconds;
      if (difference > 0) {
        if (_remainingSeconds != difference) {
          _remainingSeconds = difference;
          notifyListeners();
        }
      } else {
        _remainingSeconds = 0;
        _timer?.cancel();
        _timerFinished = true;
        _storage.clearTimerData();
        _startAlert();
        notifyListeners();
      }
    });
  }

  void adjustTimer(int delta) {
    if (_targetEndTime == null && !_timerFinished) {
      startTimer((_remainingSeconds + delta).clamp(0, 999));
      return;
    }
    if (_timerFinished) {
      resetTimer();
      startTimer(delta.abs());
      return;
    }
    _targetEndTime = _targetEndTime?.add(Duration(seconds: delta));
    _remainingSeconds = (_targetEndTime?.difference(DateTime.now()).inSeconds ?? 0).clamp(0, 999);
    if (_remainingSeconds > _initialSeconds) _initialSeconds = _remainingSeconds;
    _storage.saveTimerTargetTime(_targetEndTime!);
    notifyListeners();
  }

  void togglePause() {
    if (_timerFinished || _targetEndTime == null) return;
    if (_isPaused) {
      _targetEndTime = DateTime.now().add(Duration(seconds: _remainingSeconds));
      _storage.saveTimerTargetTime(_targetEndTime!);
      _isPaused = false;
    } else {
      _isPaused = true;
      _storage.clearTimerData();
    }
    notifyListeners();
  }

  void resetTimer() {
    _timer?.cancel();
    _targetEndTime = null;
    _remainingSeconds = 0;
    _initialSeconds = 0;
    _timerFinished = false;
    _isPaused = false;
    _storage.clearTimerData();
    stopVibration();
    notifyListeners();
  }

  void _startAlert() {
    _playAlarmSound();

    if (_useVibration) {
      Vibration.vibrate(pattern: [500, 500], repeat: 0);
    }
  }

  void stopVibration() {
    Vibration.cancel();
    FlutterRingtonePlayer().stop(); // Para o som nativo
    _audioPlayer.stop();            // Para o som de asset/custom
    _timerFinished = false;
    notifyListeners();
  }

  void setSoundEnabled(bool v) { _useSound = v; _storage.saveSoundEnabled(v); notifyListeners(); }
  void setVibrationEnabled(bool v) { _useVibration = v; _storage.saveVibrationEnabled(v); notifyListeners(); }
  void setSelectedSound(String v) { _selectedSoundType = v; _storage.saveSelectedSound(v); notifyListeners(); }
  void setCustomSound(String p) { _customSoundPath = p; _selectedSoundType = 'Custom'; _storage.saveCustomSoundPath(p); notifyListeners(); }
}