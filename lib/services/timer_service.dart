import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'storage_service.dart';

class TimerService extends ChangeNotifier {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;

  TimerService._internal() {
    _loadSettings();
    _configureAudioDucking();
  }

  final StorageService _storage = StorageService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _timer;
  Timer? _vibrationTimer;

  int _remainingSeconds = 0;
  int _initialSeconds = 0;
  bool _timerFinished = false;
  bool _isPaused = false;

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
  String? get customSoundPath => _customSoundPath;

  String get timerText => '${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}';

  void _configureAudioDucking() {
    AudioPlayer.global.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: const AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        options: [
          AVAudioSessionOptions.duckOthers,
        ],
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

  void setCustomSound(String path) {
    _customSoundPath = path;
    _selectedSoundType = 'Custom';
    _storage.saveSelectedSound('Custom');
    _storage.saveCustomSoundPath(path);
    notifyListeners();
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

  void resetTimer() {
    stopVibration();
    _timer?.cancel();
    _remainingSeconds = 0;
    _initialSeconds = 0;
    _timerFinished = false;
    _isPaused = false;
    notifyListeners();
  }

  void adjustTimer(int delta) {
    _remainingSeconds = (_remainingSeconds + delta).clamp(0, 999);
    if (_remainingSeconds > _initialSeconds) {
      _initialSeconds = _remainingSeconds;
    }

    if (_remainingSeconds > 0) {
      if (_timerFinished) {
        _timerFinished = false;
        stopVibration();
      }
      if (_timer == null || !_timer!.isActive) {
        startTimer(_remainingSeconds);
      }
    } else {
      resetTimer();
    }
    notifyListeners();
  }

  void togglePause() {
    _isPaused = !_isPaused;
    notifyListeners();
  }

  void _startAlert() async {
    if (_useSound) {
      if (_selectedSoundType == 'Custom' && _customSoundPath != null) {
        // Toca o som do dispositivo via URI ou caminho de arquivo
        _audioPlayer.play(UrlSource(_customSoundPath!));
      } else {
        AndroidSound androidSound;
        IosSound iosSound;

        switch (_selectedSoundType) {
          case 'Alarm':
            androidSound = AndroidSounds.alarm;
            iosSound = IosSounds.alarm;
            break;
          case 'Glass':
            androidSound = AndroidSounds.notification;
            iosSound = IosSounds.glass;
            break;
          case 'Ringtone':
            androidSound = AndroidSounds.ringtone;
            iosSound = IosSounds.electronic;
            break;
          default:
            androidSound = AndroidSounds.notification;
            iosSound = IosSounds.triTone;
        }

        FlutterRingtonePlayer().play(
          android: androidSound,
          ios: iosSound,
          looping: false,
          asAlarm: false,
          volume: 0.8,
        );
      }
    }

    if (_useVibration) {
      // Vibração constante: 500ms vibrando, 500ms parado. O repeat: 0 faz ser infinito.
      Vibration.vibrate(pattern: [500, 500], repeat: 0);
    }
  }

  void stopVibration() {
    _timer?.cancel();
    Vibration.cancel();
    FlutterRingtonePlayer().stop();
    _audioPlayer.stop();

    _timerFinished = false;
    notifyListeners();
  }
}