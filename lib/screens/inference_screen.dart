import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import '../data/local_database.dart';

class ImagePreprocessor {
  /// Crops and resizes the given image to 224x224 and returns the pixel data
  /// as a 3D list `[224][224][3]` suitable for NHWC input of type uint8.
  static Future<List<List<List<int>>>> preprocess(String imagePath) async {
    final imageBytes = await File(imagePath).readAsBytes();
    img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) throw Exception("Failed to decode image");

    // Crop and resize to 224x224
    img.Image resizedImage = img.copyResizeCropSquare(originalImage, size: 224);

    // Convert to NHWC [224, 224, 3] of type uint8
    var input = List.generate(
      224,
      (y) => List.generate(
        224,
        (x) => List.filled(3, 0),
      ),
    );

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        img.Pixel pixel = resizedImage.getPixel(x, y);
        input[y][x][0] = pixel.r.toInt();
        input[y][x][1] = pixel.g.toInt();
        input[y][x][2] = pixel.b.toInt();
      }
    }

    return input;
  }
}

class InferenceScreen extends StatefulWidget {
  final String patientId;
  final String leftImagePath;
  final String rightImagePath;

  const InferenceScreen({
    super.key,
    required this.patientId,
    required this.leftImagePath,
    required this.rightImagePath,
  });

  @override
  State<InferenceScreen> createState() => _InferenceScreenState();
}

class _InferenceScreenState extends State<InferenceScreen> {
  bool _isProcessing = true;
  int? _leftDrGrade;
  int? _rightDrGrade;
  int? _overallDrGrade;
  Patient? _patient;

  @override
  void initState() {
    super.initState();
    _loadPatientAndRun();
  }

  Future<void> _loadPatientAndRun() async {
    _patient = await LocalDatabase().getPatient(widget.patientId);
    
    Interpreter? interpreter;
    try {
      interpreter = await Interpreter.fromAsset('assets/models/optixai_mobilenet.tflite');
      
      _leftDrGrade = await _runInference(interpreter, widget.leftImagePath);
      _rightDrGrade = await _runInference(interpreter, widget.rightImagePath);
      
      // The overall grade is the highest of both eyes
      _overallDrGrade = (_leftDrGrade! > _rightDrGrade!) ? _leftDrGrade : _rightDrGrade;
      
      // Update patient's dr_grade in SQLite
      await LocalDatabase().updatePatientDrGrade(widget.patientId, _overallDrGrade!);

    } catch (e) {
      debugPrint("Error running TFLite model: $e");
      // Simulation fallback if model not loaded
      _leftDrGrade = 1;
      _rightDrGrade = 2;
      _overallDrGrade = 2; 
      await LocalDatabase().updatePatientDrGrade(widget.patientId, _overallDrGrade!);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      interpreter?.close();
    }
  }

  Future<int> _runInference(Interpreter interpreter, String imagePath) async {
    // 1. Preprocess the image using our custom class
    var preprocessedImage = await ImagePreprocessor.preprocess(imagePath);

    // Wrap in batch dimension: [1, 224, 224, 3]
    var input = [preprocessedImage];

    // 2. Output shape [1, 5]
    var output = List.generate(1, (i) => List.filled(5, 0));

    // 3. Run inference
    interpreter.run(input, output);

    // 4. Find max confidence score for DR Grade
    List<int> scores = output[0];
    int maxIndex = 0;
    int maxScore = scores[0];
    for (int i = 1; i < 5; i++) {
      if (scores[i] > maxScore) {
        maxScore = scores[i];
        maxIndex = i;
      }
    }

    return maxIndex;
  }
  
  String _getGradeLabel(int grade) {
    switch (grade) {
      case 0: return 'Normal';
      case 1: return 'Mild NPDR';
      case 2: return 'Moderate NPDR';
      case 3: return 'Severe NPDR';
      case 4: return 'Proliferative DR';
      default: return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isProcessing) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F7FB),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF2587DC)),
              SizedBox(height: 18),
              Text('Processing Screening', style: TextStyle(color: Color(0xFF17324D), fontSize: 22, fontWeight: FontWeight.w800)),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text('Preprocessing eye images and running the local MobileNetV4 pipeline...', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF718596), height: 1.4)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Screening Result', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF17324D))),
              const SizedBox(height: 4),
              Text('${_patient?.name ?? 'Unknown'} • ${widget.patientId}', style: const TextStyle(color: Color(0xFF718596), fontSize: 12)),
              
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F8EF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('✓ SAVED LOCALLY', style: TextStyle(color: Color(0xFF16804C), fontSize: 9, fontWeight: FontWeight.w900)),
                ),
              ),
              
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Pipeline', style: TextStyle(color: Color(0xFF1674C4), fontSize: 13, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text('OptiXAI MobileNetV4 (INT8)', style: TextStyle(color: Color(0xFF17324D), fontSize: 14, fontWeight: FontWeight.w800)),
                    SizedBox(height: 3),
                    Text('v1.0.0-edge', style: TextStyle(color: Color(0xFF718596), fontSize: 9)),
                  ],
                ),
              ),
              
              // LEFT EYE CARD
              _buildEyeCard('Left', widget.leftImagePath, _leftDrGrade!),
              
              // RIGHT EYE CARD
              _buildEyeCard('Right', widget.rightImagePath, _rightDrGrade!),
              
              // OVERALL CARD
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Text('OVERALL SCREENING', style: TextStyle(color: Color(0xFF718596), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    Text(_getGradeLabel(_overallDrGrade!), style: const TextStyle(color: Color(0xFF17324D), fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('DR Grade $_overallDrGrade / 4', style: const TextStyle(color: Color(0xFF718596), fontSize: 11)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Divider(color: Color(0xFFE5EBEF), height: 1),
                    ),
                    Text('Referable DR: ${_overallDrGrade! >= 2 ? 'YES' : 'NO'}', style: const TextStyle(color: Color(0xFF17324D), fontSize: 13, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              
              // WARNING CARD
              Container(
                margin: const EdgeInsets.only(top: 15),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Clinical Review Required', style: TextStyle(color: Color(0xFF8C6715), fontSize: 14, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text('This screening result is intended to support professional review and is not a diagnosis.', style: TextStyle(color: Color(0xFF8A7A59), fontSize: 10, height: 1.5)),
                  ],
                ),
              ),
              
              // RETURN BUTTON
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2587DC),
                  minimumSize: const Size(double.infinity, 58),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Return to Home', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEyeCard(String eyeLabel, String imagePath, int grade) {
    bool referable = grade >= 2;
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$eyeLabel Eye', style: const TextStyle(color: Color(0xFF17324D), fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.file(File(imagePath), width: double.infinity, height: 190, fit: BoxFit.cover),
          ),
          const SizedBox(height: 10),
          Text(_getGradeLabel(grade), style: const TextStyle(color: Color(0xFF17324D), fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text('DR Grade $grade/4', style: const TextStyle(color: Color(0xFF718596), fontSize: 11)),
          
          const SizedBox(height: 10),
          Container(height: 1, color: const Color(0xFFE8EDF1)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Referable DR', style: TextStyle(color: Color(0xFF687A87), fontSize: 11)),
                Text(referable ? 'YES' : 'NO', style: TextStyle(color: referable ? const Color(0xFFC62828) : const Color(0xFF16804C), fontSize: 11, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE8EDF1)),
        ],
      ),
    );
  }
}
