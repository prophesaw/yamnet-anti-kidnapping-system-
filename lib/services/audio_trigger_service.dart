import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'yamnet_classifier.dart';

/// Passive sound-trigger detection, backed by YAMNet: raw PCM audio is
/// streamed from the microphone, buffered into ~1-second windows, and
/// classified on-device. A trigger fires as soon as a distress-related class
/// (Screaming, Shout, Yell, Children shouting, Crying/sobbing, Whimper) is
/// detected above the configured confidence threshold.
class AudioTriggerService {
  final AudioRecorder _recorder = AudioRecorder();
  final YamnetClassifier _classifier = YamnetClassifier();

  StreamSubscription<Uint8List>? _pcmSub;
  final List<double> _windowBuffer = [];
  final List<int> _evidenceByteBuffer = [];
  int? _pendingPcmByte;

  static const int _evidenceSeconds = 10;
  static const int _bytesPerSample = 2;
  int get _maxEvidenceBytes =>
      YamnetClassifier.sampleRateHz * _bytesPerSample * _evidenceSeconds;

  bool _modelLoaded = false;
  bool get modelLoaded => _modelLoaded;
  String? modelLoadError;

  // --- Debug/diagnostic state, visible from the Home screen ---
  int totalBytesReceived = 0;
  String? streamError;

  final _classificationController = StreamController<
      ({String label, double confidence, bool isDistress})>.broadcast();
  Stream<({String label, double confidence, bool isDistress})>
      get classificationStream => _classificationController.stream;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> loadModel() async {
    if (_modelLoaded) return;
    try {
      await _classifier.load();
      _modelLoaded = true;
      modelLoadError = null;
    } catch (e) {
      modelLoadError = e.toString();
      // ignore: avoid_print
      print('[AudioTriggerService] Model load failed: $e');
      rethrow;
    }
  }

  Future<void> startMonitoring({
    required void Function() onTrigger,
    double confidenceThreshold = 0.3,
  }) async {
    // Do not leave a previous recorder stream active when monitoring is
    // restarted from the UI or after a cancelled incident.
    if (_pcmSub != null) {
      await stopMonitoring();
    }
    if (!await hasPermission()) {
      throw Exception('Microphone permission not granted');
    }
    if (!_modelLoaded) {
      await loadModel();
    }

    _windowBuffer.clear();
    _evidenceByteBuffer.clear();
    _pendingPcmByte = null;
    totalBytesReceived = 0;
    streamError = null;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: YamnetClassifier.sampleRateHz,
        numChannels: 1,
      ),
    );

    _pcmSub = stream.listen(
      (chunk) {
        totalBytesReceived += chunk.length;

        _evidenceByteBuffer.addAll(chunk);
        final overflow = _evidenceByteBuffer.length - _maxEvidenceBytes;
        if (overflow > 0) {
          _evidenceByteBuffer.removeRange(0, overflow);
        }

        _appendPcmChunk(chunk);

        if (_windowBuffer.length >= YamnetClassifier.requiredSampleCount) {
          final window =
              takeLast(_windowBuffer, YamnetClassifier.requiredSampleCount);
          final keepFrom = _windowBuffer.length -
              (YamnetClassifier.requiredSampleCount ~/ 4);
          _windowBuffer.removeRange(0, keepFrom.clamp(0, _windowBuffer.length));

          final result = _classifier.classify(window,
              confidenceThreshold: confidenceThreshold);

          _classificationController.add((
            label: result.topLabel,
            confidence: result.confidence,
            isDistress: result.isDistress,
          ));

          if (result.isDistress) {
            // ignore: avoid_print
            print(
                '[AudioTriggerService] Distress candidate: ${result.topLabel} '
                '(${result.confidence.toStringAsFixed(2)}) — triggering');
            onTrigger();
          }
        }
      },
      onError: (e, st) {
        streamError = e.toString();
        // ignore: avoid_print
        print('[AudioTriggerService] STREAM ERROR: $e');
      },
    );
  }

  Future<String?> stopAndGetEvidencePath() async {
    await _pcmSub?.cancel();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    if (_evidenceByteBuffer.isEmpty) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/evidence_${DateTime.now().millisecondsSinceEpoch}.wav';
      final wavBytes = _wrapPcmAsWav(
        Uint8List.fromList(_evidenceByteBuffer),
        sampleRate: YamnetClassifier.sampleRateHz,
      );
      await File(path).writeAsBytes(wavBytes);
      return path;
    } catch (e) {
      // ignore: avoid_print
      print('[AudioTriggerService] Failed to write evidence file: $e');
      return null;
    }
  }

  Future<void> stopMonitoring() async {
    await _pcmSub?.cancel();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _windowBuffer.clear();
    _evidenceByteBuffer.clear();
    _pendingPcmByte = null;
  }

  void dispose() {
    _pcmSub?.cancel();
    _recorder.dispose();
    _classifier.dispose();
    _classificationController.close();
  }

  /// `record` normally emits an even number of bytes for PCM16, but retain an
  /// odd trailing byte defensively so a sample is never split and discarded at
  /// a stream-chunk boundary.
  void _appendPcmChunk(Uint8List chunk) {
    final bytes = <int>[];
    if (_pendingPcmByte case final pending?) {
      bytes.add(pending);
      _pendingPcmByte = null;
    }
    bytes.addAll(chunk);

    if (bytes.length.isOdd) {
      _pendingPcmByte = bytes.removeLast();
    }
    if (bytes.isNotEmpty) {
      _windowBuffer.addAll(pcm16BytesToFloat32(bytes));
    }
  }

  Uint8List _wrapPcmAsWav(Uint8List pcmData, {required int sampleRate}) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLength = pcmData.length;
    final fileLength = 36 + dataLength;

    final header = BytesBuilder();
    header.add('RIFF'.codeUnits);
    header.add(_le32(fileLength));
    header.add('WAVE'.codeUnits);
    header.add('fmt '.codeUnits);
    header.add(_le32(16));
    header.add(_le16(1));
    header.add(_le16(channels));
    header.add(_le32(sampleRate));
    header.add(_le32(byteRate));
    header.add(_le16(blockAlign));
    header.add(_le16(bitsPerSample));
    header.add('data'.codeUnits);
    header.add(_le32(dataLength));
    header.add(pcmData);
    return header.toBytes();
  }

  Uint8List _le32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
  Uint8List _le16(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}
