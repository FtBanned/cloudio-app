import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

/// Web-də verilənlər bazası brauzerin IndexedDB-sində saxlanır.
Future<Database?> openCloudioDb() => databaseFactoryWeb.openDatabase('cloudio');
