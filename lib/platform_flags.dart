import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Windows masaüstü sürümü. audio_session / audio_service / video_player eklentilerinin
/// Windows desteği olmadığı için bu platformda ilgili kısımlar atlanır.
final bool kIsWindowsApp = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
