import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'inference_screen.dart';
import '../data/local_database.dart';

class CameraAlignmentScreen extends StatefulWidget {
  final String patientId;

  const CameraAlignmentScreen({super.key, required this.patientId});

  @override
  State<CameraAlignmentScreen> createState() => _CameraAlignmentScreenState();
}

class _CameraAlignmentScreenState extends State<CameraAlignmentScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _currentEye = 'Left'; // 'Left' or 'Right'
  String? _leftImagePath;
  String? _rightImagePath;
  
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _cameraController = CameraController(
        _cameras!.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<bool> checkImageQuality(String imagePath) async {
    // Simulated local quality gate (Brightness, Glare, Blur, Retina)
    await Future.delayed(const Duration(seconds: 1));
    return true; // Assume pass for demo
  }

  Future<void> _handleCapture() async {
    if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) return;
    
    setState(() { _isProcessing = true; });

    try {
      final XFile photo = await _cameraController!.takePicture();
      await _processImage(photo.path);
    } catch (e) {
      _showErrorDialog('Failed to capture image');
      setState(() { _isProcessing = false; });
    }
  }

  Future<void> _handleGalleryImage() async {
    if (_isProcessing) return;
    setState(() { _isProcessing = true; });

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await _processImage(image.path);
      } else {
        setState(() { _isProcessing = false; });
      }
    } catch (e) {
      _showErrorDialog('Failed to pick image from gallery');
      setState(() { _isProcessing = false; });
    }
  }

  Future<void> _processImage(String path) async {
    bool passed = await checkImageQuality(path);
    if (!passed) {
      setState(() { _isProcessing = false; });
      _showErrorDialog('Image failed quality check. Please retake.');
      return;
    }

    if (_currentEye == 'Left') {
      _leftImagePath = path;
      setState(() {
        _currentEye = 'Right';
        _isProcessing = false;
      });
    } else {
      _rightImagePath = path;
      // Update patient records
      await LocalDatabase().updatePatientImages(widget.patientId, _leftImagePath!, _rightImagePath!);
      
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => InferenceScreen(patientId: widget.patientId, leftImagePath: _leftImagePath!, rightImagePath: _rightImagePath!),
        ),
      );
    }
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Capture Error'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  if (_isCameraInitialized)
                    Positioned.fill(
                      child: CameraPreview(_cameraController!),
                    )
                  else
                    const Center(child: CircularProgressIndicator(color: Color(0xFF087F73))),
                    
                  // Brute Neomorphic Guide Overlay
                  Positioned.fill(
                    child: Container(
                      decoration: ShapeDecoration(
                        shape: _NeomorphicHoleShape(),
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ),

                  // Top bar
                  Positioned(
                    top: 15, left: 15, right: 15,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('Fundus Capture', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('$_currentEye Eye', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),

                  // Capture controls
                  Positioned(
                    bottom: 30, left: 0, right: 0,
                    child: Column(
                      children: [
                        if (_isProcessing)
                          const CircularProgressIndicator(color: Colors.white)
                        else
                          GestureDetector(
                            onTap: _handleCapture,
                            child: Container(
                              width: 70, height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          _isProcessing ? 'Processing...' : 'Capture $_currentEye Eye',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF087F73),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isProcessing ? null : _handleGalleryImage,
                              icon: const Icon(Icons.image),
                              label: const Text('Gallery'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeomorphicHoleShape extends ShapeBorder {
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()
        ..addOval(Rect.fromCenter(
          center: Offset(rect.width / 2, rect.height / 2 - 50),
          width: 250,
          height: 250,
        ))
        ..close(),
    );
  }
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
  @override
  ShapeBorder scale(double t) => this;
}
