import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/local_database.dart';
import 'camera_alignment_screen.dart';

class NewPatientScreen extends StatefulWidget {
  const NewPatientScreen({super.key});

  @override
  State<NewPatientScreen> createState() => _NewPatientScreenState();
}

class _NewPatientScreenState extends State<NewPatientScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  Future<void> _handleSave({bool startScreening = false}) async {
    final name = _nameController.text.trim();
    final ageText = _ageController.text.trim();
    final gender = _genderController.text.trim();
    final stateStr = _stateController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || ageText.isEmpty || gender.isEmpty || stateStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields.')),
      );
      return;
    }

    final String patientId = 'DR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}-${const Uuid().v4().substring(0, 4)}';

    final patient = Patient(
      id: patientId,
      name: name,
      age: int.tryParse(ageText) ?? 0,
      gender: gender,
      diabetesDetails: stateStr, // Map 'state' from UI to diabetesDetails/state
      phone: phone,
      createdAt: DateTime.now().toIso8601String(),
    );

    await LocalDatabase().insertPatient(patient);

    if (!mounted) return;

    if (startScreening) {
      // Navigate directly to camera flow with the new patient's ID
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CameraAlignmentScreen(patientId: patientId),
        ),
      );
    } else {
      // Return patientId to the caller so the dashboard can link to screening
      Navigator.of(context).pop(patientId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New Patient',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF12304A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Register the patient locally. Internet is not required.',
                style: TextStyle(
                  color: Color(0xFF718294),
                  height: 1.4,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 25),
              _Field(
                label: 'Full Name *',
                controller: _nameController,
              ),
              _Field(
                label: 'Age *',
                controller: _ageController,
                keyboardType: TextInputType.number,
              ),
              _Field(
                label: 'Gender *',
                controller: _genderController,
              ),
              _Field(
                label: 'State *',
                controller: _stateController,
              ),
              _Field(
                label: 'Phone',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
              ),
              Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offline Registration',
                      style: TextStyle(
                        color: Color(0xFF22764F),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Patient data is stored locally and placed in the synchronization queue.',
                      style: TextStyle(
                        color: Color(0xFF507565),
                        height: 1.35,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: () => _handleSave(startScreening: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0f766e),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Register & Start Screening',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => _handleSave(startScreening: false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: Color(0xFF208AEF)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Register Only',
                  style: TextStyle(
                    color: Color(0xFF208AEF),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xFF63788B),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;

  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF314B61),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(
              color: Color(0xFF17354D),
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: label.replaceAll(' *', ''),
              hintStyle: const TextStyle(color: Color(0xFFA0ACB8)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFDCE5ED)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF208AEF)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
