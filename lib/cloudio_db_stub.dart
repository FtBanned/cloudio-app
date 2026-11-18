import 'package:sembast/sembast.dart';

/// Nə web, nə də dart:io olan platformalarda saxlama yoxdur: null qaytarır.
/// (Web üçün cloudio_db_web.dart, telefon üçün cloudio_db_io.dart istifadə olunur.)
Future<Database?> openCloudioDb() async => null;