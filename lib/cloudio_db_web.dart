import 'package:sembast_web/sembast_web.dart';

/// Web-də verilənlər bazası brauzerin IndexedDB-sində saxlanır.
Future<Database?> openCloudioDb() => databaseFactoryWeb.openDatabase('cloudio');

/// Yedəkdən bərpa yalnız telefonda var.
Future<Database?> importCloudioDb(Map<String, Object?> content) async => null;
