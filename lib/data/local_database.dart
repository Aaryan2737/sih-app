import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class Patient {
  final String id;
  final String name;
  final int age;
  final String gender;
  final String diabetesDetails;
  final String phone;
  final String createdAt;
  String syncStatus;
  String? leftEyeImagePath;
  String? rightEyeImagePath;
  int? drGrade;

  Patient({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.diabetesDetails,
    required this.phone,
    required this.createdAt,
    this.syncStatus = 'pending',
    this.leftEyeImagePath,
    this.rightEyeImagePath,
    this.drGrade,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'gender': gender,
      'diabetes_details': diabetesDetails,
      'phone': phone,
      'createdAt': createdAt,
      'syncStatus': syncStatus,
      'left_eye_image_path': leftEyeImagePath,
      'right_eye_image_path': rightEyeImagePath,
      'dr_grade': drGrade,
    };
  }

  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'],
      name: map['name'],
      age: map['age'],
      gender: map['gender'],
      diabetesDetails: map['diabetes_details'],
      phone: map['phone'],
      createdAt: map['createdAt'],
      syncStatus: map['syncStatus'],
      leftEyeImagePath: map['left_eye_image_path'],
      rightEyeImagePath: map['right_eye_image_path'],
      drGrade: map['dr_grade'],
    );
  }
}

class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._internal();
  factory LocalDatabase() => _instance;
  LocalDatabase._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDB();
    return _database!;
  }

  Future<Database> initDB() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'optixai.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE patients (
            id TEXT PRIMARY KEY,
            name TEXT,
            age INTEGER,
            gender TEXT,
            diabetes_details TEXT,
            phone TEXT,
            createdAt TEXT,
            syncStatus TEXT,
            left_eye_image_path TEXT,
            right_eye_image_path TEXT,
            dr_grade INTEGER
          )
        ''');
      },
    );
  }

  Future<void> insertPatient(Patient patient) async {
    final db = await database;
    await db.insert('patients', patient.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Patient>> getPendingPatients() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'patients',
      where: 'syncStatus = ?',
      whereArgs: ['pending'],
    );
    return List.generate(maps.length, (i) => Patient.fromMap(maps[i]));
  }
  
  Future<List<Patient>> getAllPatients() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('patients', orderBy: 'createdAt DESC');
    return List.generate(maps.length, (i) => Patient.fromMap(maps[i]));
  }

  Future<void> updatePatientSyncStatus(String id, String status) async {
    final db = await database;
    await db.update(
      'patients',
      {'syncStatus': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<void> updatePatientImages(String id, String leftPath, String rightPath) async {
    final db = await database;
    await db.update(
      'patients',
      {
        'left_eye_image_path': leftPath,
        'right_eye_image_path': rightPath,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<void> updatePatientDrGrade(String id, int grade) async {
    final db = await database;
    await db.update(
      'patients',
      {'dr_grade': grade},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<Patient?> getPatient(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'patients',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Patient.fromMap(maps.first);
    }
    return null;
  }
}
