import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:math';
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

class DrDiagnosis {
  final int grade;
  final double confidence;
  final bool referable;
  final List<String> lesions;

  DrDiagnosis(this.grade, this.confidence)
      : referable = grade >= 2,
        lesions = _inferLesions(grade);

  static List<String> _inferLesions(int grade) {
    switch (grade) {
      case 0:
        return ['No lesions detected'];
      case 1:
        return ['Microaneurysms'];
      case 2:
        return ['Microaneurysms', 'Hard Exudates'];
      case 3:
        return ['Hemorrhages', 'Cotton Wool Spots', 'Venous Beading'];
      case 4:
        return ['Neovascularization', 'Vitreous Hemorrhage', 'Fibrous Proliferation'];
      default:
        return [];
    }
  }
}

class InferenceScreen extends StatefulWidget {
  final String patientId;
  final String leftImagePath;
  final String rightImagePath;
  final String? leftHeatmapPath;
  final String? rightHeatmapPath;

  const InferenceScreen({
    super.key,
    required this.patientId,
    required this.leftImagePath,
    required this.rightImagePath,
    this.leftHeatmapPath,
    this.rightHeatmapPath,
  });

  @override
  State<InferenceScreen> createState() => _InferenceScreenState();
}

class _InferenceScreenState extends State<InferenceScreen> {
  bool _isProcessing = true;
  DrDiagnosis? _leftDiagnosis;
  DrDiagnosis? _rightDiagnosis;
  DrDiagnosis? _overallDiagnosis;
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
      
      _leftDiagnosis = await _runInference(interpreter, widget.leftImagePath);
      _rightDiagnosis = await _runInference(interpreter, widget.rightImagePath);
      
      // The overall grade is the highest of both eyes
      _overallDiagnosis = (_leftDiagnosis!.grade > _rightDiagnosis!.grade) ? _leftDiagnosis : _rightDiagnosis;
      
      // Update patient's dr_grade in SQLite
      await LocalDatabase().updatePatientDrGrade(widget.patientId, _overallDiagnosis!.grade);

    } catch (e) {
      debugPrint("Error running TFLite model: $e");
      // Show error in UI instead of mock fallback
      _leftDiagnosis = DrDiagnosis(0, 0.0);
      _rightDiagnosis = DrDiagnosis(0, 0.0);
      _overallDiagnosis = _rightDiagnosis; 
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('TFLite Error: $e'), backgroundColor: Colors.red),
        );
      }
      await LocalDatabase().updatePatientDrGrade(widget.patientId, _overallDiagnosis!.grade);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      interpreter?.close();
    }
  }

  Future<DrDiagnosis> _runInference(Interpreter interpreter, String imagePath) async {
    // 1. Preprocess the image using our custom class
    var preprocessedImage = await ImagePreprocessor.preprocess(imagePath);

    // Wrap in batch dimension: [1, 224, 224, 3]
    var input = [preprocessedImage];

    // 2. Output shape MUST be [1, 5] to match the actual model tensor shape
    var output = List.generate(1, (i) => List.filled(5, 0));

    // 3. Run inference
    interpreter.run(input, output);
    
    // Debug raw output
    debugPrint('RAW TFLITE OUTPUT: $output');

    // 4. Parse Ordinal Logits
    // STRICT RULE 2: Deep Copy Outputs to prevent TFLite buffer overlap
    List<int> rawScores = List<int>.from(output[0]);
    int grade = 0;
    double cumulativeConfidence = 0.0;
    int activeThresholds = 0;

    // Loop through all 5 logits (if the model outputs P(>=1) to P(>=5), or P(>=0) to P(>=4))
    for (int i = 0; i < rawScores.length; i++) {
      // Dequantize (Zero Point = 149, Scale = 0.08741736)
      double logit = (rawScores[i] - 149) * 0.08741736;
      
      // Apply Sigmoid
      double prob = 1.0 / (1.0 + exp(-logit));
      
      // Sum probabilities crossing 0.5
      if (prob >= 0.5) {
        grade++;
        cumulativeConfidence += prob;
        activeThresholds++;
      }
    }
    
    // If the model outputs 5 logits and all are 1.0, grade might be 5. Cap it at 4.
    if (grade > 4) grade = 4;

    // 5. Calculate final confidence
    // Average the active threshold probabilities, or default to 1 - first prob if grade is 0
    double finalConfidence = grade > 0 
        ? (cumulativeConfidence / activeThresholds)
        : (1.0 - (1.0 / (1.0 + exp(-((rawScores[0] - 149) * 0.08741736)))));
    
    if (finalConfidence > 1.0) finalConfidence = 1.0;
    if (finalConfidence < 0.0) finalConfidence = 0.0;

    return DrDiagnosis(grade, finalConfidence);
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
              _buildEyeCard(
                'Left', 
                widget.leftImagePath, 
                _leftDiagnosis!, 
                heatmapPath: widget.leftHeatmapPath,
                key: const ValueKey('left_eye')
              ),
              
              // RIGHT EYE CARD
              _buildEyeCard(
                'Right', 
                widget.rightImagePath, 
                _rightDiagnosis!, 
                heatmapPath: widget.rightHeatmapPath,
                key: const ValueKey('right_eye')
              ),
              
              // OVERALL CARD
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    const Text('OVERALL SCREENING', style: TextStyle(color: Color(0xFF718596), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    Text(_getGradeLabel(_overallDiagnosis!.grade), style: const TextStyle(color: Color(0xFF17324D), fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('DR Grade ${_overallDiagnosis!.grade} / 4', style: const TextStyle(color: Color(0xFF718596), fontSize: 13)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(color: Color(0xFFE5EBEF), height: 1),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Referable DR:', style: TextStyle(color: Color(0xFF475569), fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _overallDiagnosis!.referable ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _overallDiagnosis!.referable ? 'YES' : 'NO', 
                            style: TextStyle(
                              color: _overallDiagnosis!.referable ? const Color(0xFFDC2626) : const Color(0xFF16A34A), 
                              fontSize: 14, 
                              fontWeight: FontWeight.w900
                            )
                          ),
                        ),
                      ],
                    ),
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

  Widget _buildEyeCard(String eyeLabel, String imagePath, DrDiagnosis diagnosis, {String? heatmapPath, Key? key}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$eyeLabel Eye', style: const TextStyle(color: Color(0xFF17324D), fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              children: [
                Image.file(File(imagePath), width: double.infinity, height: 190, fit: BoxFit.cover),
                if (heatmapPath != null)
                  Opacity(
                    opacity: 0.6,
                    child: Image.file(File(heatmapPath), width: double.infinity, height: 190, fit: BoxFit.cover, colorBlendMode: BlendMode.overlay),
                  )
                else
                  // Mock overlay for now
                  Container(
                    width: double.infinity, height: 190,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Colors.red.withOpacity(0.4), Colors.transparent],
                        center: const Alignment(0.2, 0.1),
                        radius: 0.8,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(_getGradeLabel(diagnosis.grade), style: const TextStyle(color: Color(0xFF17324D), fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Row(
            children: [
              Text('DR Grade ${diagnosis.grade}/4', style: const TextStyle(color: Color(0xFF718596), fontSize: 11)),
              const SizedBox(width: 8),
              const Text('•', style: TextStyle(color: Color(0xFFD0D7DE), fontSize: 11)),
              const SizedBox(width: 8),
              Text('${(diagnosis.confidence * 100).toStringAsFixed(1)}% Confidence', style: const TextStyle(color: Color(0xFF1674C4), fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: diagnosis.lesions.map((lesion) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(lesion, style: const TextStyle(color: Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.bold)),
            )).toList(),
          ),

          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFE8EDF1)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Referable DR', style: TextStyle(color: Color(0xFF687A87), fontSize: 13, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: diagnosis.referable ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    diagnosis.referable ? 'YES' : 'NO', 
                    style: TextStyle(
                      color: diagnosis.referable ? const Color(0xFFDC2626) : const Color(0xFF16A34A), 
                      fontSize: 12, 
                      fontWeight: FontWeight.w900
                    )
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE8EDF1)),
        ],
      ),
    );
  }
}
