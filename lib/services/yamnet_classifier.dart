import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Runs YAMNet locally to identify distress-related sounds.
///
/// YAMNet consumes 15,600 mono 16 kHz samples normalized to [-1, 1]. Its
/// scores are independent class probabilities, so they must not be softmaxed.
class YamnetClassifier {
  static const String _modelAsset = 'assets/models/yamnet.tflite';
  static const String _labelsAsset = 'assets/models/yamnet_class_map.csv';

  static const int requiredSampleCount = 15600;
  static const int sampleRateHz = 16000;
  static const int classCount = 521;

  /// Shout, Yell, Children shouting, Screaming, Crying/sobbing, Whimper.
  static const Set<int> distressClassIndices = {6, 9, 10, 11, 19, 21};

  Interpreter? _interpreter;
  List<String> _labels = const [];
  bool _inputHasBatchDimension = false;

  bool get isReady => _interpreter != null;

  Future<void> load() async {
    if (isReady) return;

    final interpreter = await Interpreter.fromAsset(_modelAsset);
    try {
      var inputShape = interpreter.getInputTensor(0).shape;
      // This YAMNet export has a dynamic waveform dimension. TFLite reports
      // its unallocated placeholder as [1], so assign a one-second window
      // before reading the final input/output tensor shapes.
      if (inputShape.length == 1 && inputShape.single == 1) {
        interpreter.resizeInputTensor(0, [requiredSampleCount]);
        interpreter.allocateTensors();
        inputShape = interpreter.getInputTensor(0).shape;
      }
      if (!_isSupportedInputShape(inputShape)) {
        throw StateError(
          'Unsupported YAMNet input shape: $inputShape. Expected [15600] or [1, 15600].',
        );
      }

      final scoreShape = interpreter.getOutputTensor(0).shape;
      if (scoreShape.isEmpty || scoreShape.last != classCount) {
        throw StateError('Unsupported YAMNet score output shape: $scoreShape.');
      }

      final labels = await _loadLabels();
      if (labels.length < classCount) {
        throw StateError(
            'YAMNet class map has ${labels.length} labels; expected $classCount.');
      }

      _inputHasBatchDimension = inputShape.length == 2;
      _labels = labels;
      _interpreter = interpreter;
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  bool _isSupportedInputShape(List<int> shape) =>
      (shape.length == 1 && shape[0] == requiredSampleCount) ||
      (shape.length == 2 && shape[0] == 1 && shape[1] == requiredSampleCount);

  Future<List<String>> _loadLabels() async {
    final lines = (await rootBundle.loadString(_labelsAsset))
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    return lines.skip(1).map((line) {
      final fields = line.split(',');
      return fields.sublist(2).join(',').replaceAll('"', '').trim();
    }).toList(growable: false);
  }

  /// Classifies one approximately one-second audio window.
  YamnetClassification classify(
    List<double> waveform, {
    double confidenceThreshold = 0.3,
  }) {
    final interpreter = _interpreter;
    if (interpreter == null) return YamnetClassification.notReady;

    final samples = List<double>.filled(requiredSampleCount, 0);
    samples.setRange(
        0, math.min(waveform.length, requiredSampleCount), waveform);

    final scoreShape = interpreter.getOutputTensor(0).shape;
    final frameCount = scoreShape
        .sublist(0, scoreShape.length - 1)
        .fold<int>(1, (product, dimension) => product * dimension);
    final scores = List.generate(
      frameCount,
      (_) => List<double>.filled(classCount, 0),
      growable: false,
    );

    try {
      // YAMNet publishes auxiliary embeddings/spectrogram outputs as well as
      // class scores. `run()` attempts to copy every output tensor and fails
      // when no buffers are supplied for those auxiliary values. Invoke the
      // graph, then copy only output 0 (the 521-class score tensor).
      interpreter.runInference([
        _inputHasBatchDimension ? [samples] : samples,
      ]);
      interpreter.getOutputTensor(0).copyTo(scores);
    } catch (_) {
      return YamnetClassification.inferenceError;
    }

    var bestClassIndex = -1;
    var bestScore = 0.0;
    for (final classIndex in distressClassIndices) {
      // Some YAMNet exports return several overlapping score frames. Average
      // them so a trigger is not based on an isolated short-frame spike.
      final score = scores.fold<double>(
            0,
            (sum, frame) => sum + frame[classIndex],
          ) /
          frameCount;
      if (score > bestScore) {
        bestScore = score;
        bestClassIndex = classIndex;
      }
    }

    return YamnetClassification(
      isDistress: bestScore >= confidenceThreshold,
      topLabel: bestClassIndex == -1 ? 'none' : _labels[bestClassIndex],
      confidence: bestScore,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

class YamnetClassification {
  const YamnetClassification({
    required this.isDistress,
    required this.topLabel,
    required this.confidence,
  });

  static const notReady = YamnetClassification(
    isDistress: false,
    topLabel: 'not_ready',
    confidence: 0,
  );

  static const inferenceError = YamnetClassification(
    isDistress: false,
    topLabel: 'inference_error',
    confidence: 0,
  );

  final bool isDistress;
  final String topLabel;
  final double confidence;
}

/// Converts little-endian PCM16 chunks from `record` to YAMNet samples.
List<double> pcm16BytesToFloat32(List<int> bytes) {
  final samples = <double>[];
  for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
    final unsigned = bytes[offset] | (bytes[offset + 1] << 8);
    final signed = unsigned >= 0x8000 ? unsigned - 0x10000 : unsigned;
    samples.add(signed / 32768.0);
  }
  return samples;
}

/// Returns a copy so callers can retain their rolling sample buffer.
List<double> takeLast(List<double> data, int count) => data.length <= count
    ? List<double>.from(data)
    : data.sublist(data.length - count);
