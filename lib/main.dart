import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'core/constants.dart';
import 'data/local_database.dart';
import 'services/supabase_sync_service.dart';
import 'screens/new_patient_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env file: $e");
  }

  // Try to initialize Supabase
  try {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );
  } catch (e) {
    debugPrint("Supabase not initialized: $e");
  }

  runApp(const OptiXAIApp());
}

class OptiXAIApp extends StatelessWidget {
  const OptiXAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptiXAI',
      theme: AppStyles.theme,
      home: const DashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  String _connectionStatus = 'offline';
  int _totalPatients = 0;
  int _completedScreenings = 0;
  int _moderateRisk = 0;
  int _highRisk = 0;
  int _pendingSync = 0;
  List<Patient> _recentScreenings = [];

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    SupabaseSyncService().startAutoSync();
    _loadDashboard();
    _checkInitialConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    SupabaseSyncService().stopAutoSync();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _updateConnectionStatus(results);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (mounted) {
      setState(() {
        _connectionStatus = results.any((r) => r != ConnectivityResult.none) ? 'online' : 'offline';
      });
    }
  }

  Future<void> _loadDashboard() async {
    setState(() { _isLoading = true; });
    final db = LocalDatabase();
    final patients = await db.getAllPatients();
    final pending = await db.getPendingPatients();

    int completed = 0;
    int modRisk = 0;
    int hiRisk = 0;

    for (var p in patients) {
      if (p.drGrade != null) {
        completed++;
        if (p.drGrade! == 2 || p.drGrade! == 3) modRisk++;
        if (p.drGrade! == 4) hiRisk++;
      }
    }

    setState(() {
      _totalPatients = patients.length;
      _completedScreenings = completed;
      _moderateRisk = modRisk;
      _highRisk = hiRisk;
      _pendingSync = pending.length;
      _recentScreenings = patients.take(3).toList();
      _isLoading = false;
    });
  }

  Future<void> _syncData() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Starting synchronization...')),
    );
    await SupabaseSyncService().syncPendingPatients();
    await _loadDashboard();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Synchronization complete')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.brandTeal),
              SizedBox(height: 18),
              Text('Loading OptiXAI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
              SizedBox(height: 7),
              Text('Preparing your screening dashboard...', style: TextStyle(color: AppColors.secondaryText)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 50),
            children: [
              // HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('OptiXAI', style: TextStyle(color: AppColors.brandTeal, fontSize: 16, fontWeight: FontWeight.w900)),
                        Text('Health Worker Dashboard', style: TextStyle(color: AppColors.primaryText, fontSize: 25, fontWeight: FontWeight.w800, height: 1.2)),
                        SizedBox(height: 5),
                        Text('Offline-first diabetic retinopathy screening', style: TextStyle(color: AppColors.secondaryText, fontSize: 13, height: 1.4)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _connectionStatus == 'online' ? const Color(0xFFdcfce7) : AppColors.offlineBadgeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text('● ', style: TextStyle(fontSize: 11, color: _connectionStatus == 'online' ? const Color(0xFF166534) : AppColors.offlineBadgeText)),
                        Text(_connectionStatus == 'online' ? 'Online' : 'Offline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _connectionStatus == 'online' ? const Color(0xFF166534) : AppColors.offlineBadgeText)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // OFFLINE CARD
              if (_connectionStatus == 'offline')
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.offlineCardBg,
                    border: Border.all(color: AppColors.offlineCardBorder),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: AppColors.offlineIconBg, borderRadius: BorderRadius.circular(21)),
                        child: const Center(child: Text('⌁', style: TextStyle(color: AppColors.offlineIconText, fontSize: 24))),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Working Offline', style: TextStyle(color: Color(0xFF9f1239), fontSize: 15, fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text('Patient records and screening data will remain on this device until internet connectivity returns.', style: TextStyle(color: Color(0xFF881337), fontSize: 12, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
              if (_connectionStatus == 'online' && _pendingSync > 0)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFdcfce7),
                    border: Border.all(color: const Color(0xFFbbf7d0)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: const Color(0xFF22c55e), borderRadius: BorderRadius.circular(21)),
                        child: const Center(child: Text('✓', style: TextStyle(color: Colors.white, fontSize: 24))),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Connection Restored', style: TextStyle(color: Color(0xFF166534), fontSize: 15, fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text('Pending records can be synchronized when the backend is available.', style: TextStyle(color: Color(0xFF15803d), fontSize: 12, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
              if (_connectionStatus == 'offline' || (_connectionStatus == 'online' && _pendingSync > 0))
                const SizedBox(height: 20),

              // TODAY'S SCREENING
              const Text("Today's Screening", style: TextStyle(color: AppColors.primaryText, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatCard(_totalPatients, 'Patients', '👤'),
                  _buildStatCard(_completedScreenings, 'Completed', '✓'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatCard(_moderateRisk, 'Moderate Risk', '!'),
                  _buildStatCard(_highRisk, 'High Risk', '!'),
                ],
              ),
              const SizedBox(height: 22),

              // SYNC CARD
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Synchronization', style: TextStyle(color: AppColors.primaryText, fontSize: 18, fontWeight: FontWeight.w800)),
                            SizedBox(height: 3),
                            Text('Store-and-forward data', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                          ],
                        ),
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(color: AppColors.syncCountBg, borderRadius: BorderRadius.circular(14)),
                          child: Center(child: Text('$_pendingSync', style: const TextStyle(color: AppColors.syncCountText, fontSize: 21, fontWeight: FontWeight.w900))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _pendingSync == 0 ? 'No records are currently waiting for synchronization.' : '$_pendingSync records waiting for backend synchronization.',
                      style: const TextStyle(color: AppColors.secondaryText, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Network', style: TextStyle(color: AppColors.secondaryText, fontSize: 13)),
                        Text(_connectionStatus == 'online' ? 'Connected' : 'Offline', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _connectionStatus == 'online' ? AppColors.brandTeal : AppColors.offlineBadgeText)),
                      ],
                    ),
                    if (_connectionStatus == 'online' && _pendingSync > 0) ...[
                      const SizedBox(height: 15),
                      ElevatedButton(
                        onPressed: _syncData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandTeal,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Sync Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      )
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // QUICK ACTIONS
              const Text('Quick Actions', style: TextStyle(color: AppColors.primaryText, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildActionButton('+', 'New Patient', 'Register a patient', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NewPatientScreen())).then((_) => _loadDashboard());
                    }),
                    const Divider(color: AppColors.border, height: 1),
                    _buildActionButton('◉', 'Start Screening', 'Capture fundus image', () {}),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // ARCHITECTURE CARD
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFf0fdfa),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFccfbf1)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OptiXAI Offline Architecture', style: TextStyle(color: Color(0xFF115e59), fontSize: 16, fontWeight: FontWeight.w900)),
                    SizedBox(height: 8),
                    Text('Capture → Quality Gate → AI → Grad-CAM → Local Storage → Sync', style: TextStyle(color: AppColors.brandTeal, fontSize: 12, fontWeight: FontWeight.w800, height: 1.5)),
                    SizedBox(height: 7),
                    Text('The mobile workflow is designed to continue functioning when internet connectivity is unavailable.', style: TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('DEMO SCREENING SYSTEM — AI predictions must be generated by a validated model before clinical use. OptiXAI does not replace examination by a qualified eye-care professional.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText, fontSize: 10, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(int value, String label, String icon) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.43,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.actionIconBg, borderRadius: BorderRadius.circular(18)),
            child: Center(child: Text(icon, style: const TextStyle(color: AppColors.brandTeal, fontSize: 16, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(height: 10),
          Text('$value', style: const TextStyle(color: AppColors.primaryText, fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: AppColors.secondaryText, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActionButton(String icon, String title, String subtitle, VoidCallback onPress) {
    return InkWell(
      onTap: onPress,
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: AppColors.actionIconBg, borderRadius: BorderRadius.circular(15)),
              child: Center(child: Text(icon, style: const TextStyle(color: AppColors.brandTeal, fontSize: 21, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.primaryText, fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                ],
              ),
            ),
            const Text('›', style: TextStyle(color: Color(0xFF94a3b8), fontSize: 27)),
          ],
        ),
      ),
    );
  }
}
