import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String createAudioUrl(Uint8List bytes, String mime) {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  return web.URL.createObjectURL(blob);
}

void revokeAudioUrl(String url) => web.URL.revokeObjectURL(url);
