import 'dart:io';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/local_database.dart';
import 'package:flutter/foundation.dart';

class SupabaseSyncService {
  static final SupabaseSyncService _instance = SupabaseSyncService._internal();
  factory SupabaseSyncService() => _instance;
  SupabaseSyncService._internal();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  Timer? _syncTimer;

  void startAutoSync() {
    // Prevent multiple timers
    if (_syncTimer != null) return;
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      syncPendingPatients();
    });
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> syncPendingPatients() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    try {
      final db = LocalDatabase();
      final pendingPatients = await db.getPendingPatients();

      if (pendingPatients.isEmpty) {
        _isSyncing = false;
        return;
      }

      final supabase = Supabase.instance.client;

      for (var patient in pendingPatients) {
        String? leftUrl;
        String? rightUrl;

        // Upload Left Eye
        if (patient.leftEyeImagePath != null && File(patient.leftEyeImagePath!).existsSync()) {
          final fileName = '\${patient.id}_left.jpg';
          await supabase.storage.from('fundus_images').upload(
            fileName,
            File(patient.leftEyeImagePath!),
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
          leftUrl = supabase.storage.from('fundus_images').getPublicUrl(fileName);
        }

        // Upload Right Eye
        if (patient.rightEyeImagePath != null && File(patient.rightEyeImagePath!).existsSync()) {
          final fileName = '\${patient.id}_right.jpg';
          await supabase.storage.from('fundus_images').upload(
            fileName,
            File(patient.rightEyeImagePath!),
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
          rightUrl = supabase.storage.from('fundus_images').getPublicUrl(fileName);
        }

        // Insert Record into PostgreSQL
        await supabase.from('patients').upsert({
          'id': patient.id,
          'name': patient.name,
          'age': patient.age,
          'gender': patient.gender,
          'diabetes_details': patient.diabetesDetails,
          'phone': patient.phone,
          'created_at': patient.createdAt,
          'left_eye_image_url': leftUrl,
          'right_eye_image_url': rightUrl,
          'dr_grade': patient.drGrade,
        });

        // Mark as synced locally
        await db.updatePatientSyncStatus(patient.id, 'synced');
      }
      debugPrint("Auto-sync completed successfully.");
    } catch (e) {
      debugPrint("Sync Error: \$e");
    } finally {
      _isSyncing = false;
    }
  }
}
