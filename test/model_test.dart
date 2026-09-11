import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Load OptiXAI MobileNet model and verify input/output shapes', () async {
    final modelFile = File('assets/models/optixai_mobilenet.tflite');
    expect(await modelFile.exists(), isTrue, reason: 'Model file does not exist');

    try {
      final interpreter = await Interpreter.fromFile(modelFile);
      
      print('Model loaded successfully!');
      
      final inputTensors = interpreter.getInputTensors();
      print('Input Tensors:');
      for (var tensor in inputTensors) {
        print(' - Name: ${tensor.name}');
        print(' - Type: ${tensor.type}');
        print(' - Shape: ${tensor.shape}');
      }

      final outputTensors = interpreter.getOutputTensors();
      print('Output Tensors:');
      for (var tensor in outputTensors) {
        print(' - Name: ${tensor.name}');
        print(' - Type: ${tensor.type}');
        print(' - Shape: ${tensor.shape}');
      }

      interpreter.close();
    } catch (e) {
      print('Failed to load model: $e');
      fail('Model loading failed: $e');
    }
  });
}
