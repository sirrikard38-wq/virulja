import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../src/domain/exif.dart';
import '../src/domain/models.dart';
import 'store.dart';

/// The copy of a photo the app keeps: sharp on a phone, about 1 MB. The
/// original stays in the phone's gallery.
const int _fullSide = 2048;
const double _fullQuality = 0.82;
const int _thumbSide = 420;
const double _thumbQuality = 0.7;

/// The Exif block is at the very start of a photo file.
const int _exifBytes = 256 * 1024;

/// The small picture of photo [id] for lists and grids.
String thumbId(String id) => '$id.t';

Future<web.Blob> _shrink(web.ImageBitmap picture, int maxSide, double quality) {
  final done = Completer<web.Blob>();
  final scale = min(1.0, maxSide / max(picture.width, picture.height));
  final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
    ..width = (picture.width * scale).round()
    ..height = (picture.height * scale).round();
  (canvas.getContext('2d') as web.CanvasRenderingContext2D)
      .drawImage(picture, 0, 0, canvas.width, canvas.height);
  canvas.toBlob(
    ((web.Blob? blob) {
      if (blob == null) {
        done.completeError(StateError('no picture'));
      } else {
        done.complete(blob);
      }
    }).toJS,
    'image/jpeg',
    quality.toJS,
  );
  return done.future;
}

/// Stores a shrunken copy and a small picture of [file] under [id].
Future<void> storePicture(AppStore store, String id, web.File file) async {
  final picture = await web.window.createImageBitmap(file).toDart;
  try {
    await store.putBlob(id, await _shrink(picture, _fullSide, _fullQuality));
    await store.putBlob(
        thumbId(id), await _shrink(picture, _thumbSide, _thumbQuality));
  } finally {
    picture.close();
  }
}

/// When the file says it was taken; the file's own date when it does not say.
DateTime _wallClock(int millisecondsSinceEpoch) {
  final local = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  return DateTime.utc(local.year, local.month, local.day, local.hour,
      local.minute, local.second);
}

/// Turns a picked file into a [Photo] of the trip, or null if it is not a
/// picture this phone can read.
Future<Photo?> importPhoto(AppStore store, web.File file, String addedBy) async {
  try {
    final head = await file.slice(0, _exifBytes).arrayBuffer().toDart;
    final facts = readExif(Uint8List.view(head.toDart));
    final id = store.newId();
    await storePicture(store, id, file);
    return Photo(
      id: id,
      takenAt: facts.takenAt ?? _wallClock(file.lastModified),
      addedBy: addedBy,
      latitude: facts.latitude,
      longitude: facts.longitude,
    );
  } on Object {
    return null;
  }
}

/// The files picked in a file input.
List<web.File> pickedFiles(web.HTMLInputElement input) {
  final files = input.files;
  if (files == null) return const [];
  return [for (var i = 0; i < files.length; i++) files.item(i)!];
}
