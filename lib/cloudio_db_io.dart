import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

/// Telefonda (iOS/Android) və masaüstündə baza tətbiqin xüsusi qovluğundakı
/// "cloudio.db" faylında saxlanır (tətbiq bağlanıb açılsa da qalır).
Future<Database?> openCloudioDb() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return databaseFactoryIo.openDatabase('${dir.path}/cloudio.db');
}