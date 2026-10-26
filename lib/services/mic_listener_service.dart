import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'live_chord_detector.dart';

/// Listens to the microphone and publishes the chord and note heard.
class MicListenerService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  static const int _sampleRate = 44100;
  static const Duration _interval = Duration(milliseconds: 300);

  LiveChordDetector? _detector;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  bool _busy = false;

  bool _listening = false;
  bool get listening => _listening;

  String? _error;
  String? get error => _error;

  LiveDetection _detection = LiveDetection.silent;
  LiveDetection get detection => _detection;

  /// Most recent distinct chords, newest last.
  final List<String> history = [];

  Future<void> start() async {
    if (_listening) return;
    _error = null;
    try {
      if (!await _recorder.hasPermission()) {
        _error = 'Accès au micro refusé. Autorise le micro dans les réglages.';
        notifyListeners();
        return;
      }
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      _detector = LiveChordDetector(sampleRate: _sampleRate);
      _subscription = stream.listen(
        (chunk) => _detector?.feedPcm16(chunk),
        onError: (Object e) {
          _error = 'Micro interrompu : $e';
          unawaited(stop());
        },
      );
      _timer = Timer.periodic(_interval, (_) => _tick());
      _listening = true;
      history.clear();
      _detection = LiveDetection.silent;
      notifyListeners();
    } catch (e) {
      _error = 'Impossible de démarrer le micro : ${e.toString().split('\n').first}';
      _listening = false;
      notifyListeners();
    }
  }

  Future<void> _tick() async {
    final detector = _detector;
    if (detector == null || _busy) return;
    _busy = true;
    try {
      final window = detector.snapshot();
      final result = kIsWeb
          ? LiveChordDetector.analyzeWindow(window, _sampleRate)
          : await Isolate.run(() => LiveChordDetector.analyzeWindow(window, _sampleRate));
      if (!_listening) return;
      _detection = result;
      final chord = result.chord;
      if (chord != null && (history.isEmpty || history.last != chord)) {
        history.add(chord);
        if (history.length > 16) history.removeAt(0);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[MicListenerService] analysis error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    _detector = null;
    if (_listening) {
      _listening = false;
      try {
        await _recorder.stop();
      } catch (e) {
        debugPrint('[MicListenerService] stop error: $e');
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
