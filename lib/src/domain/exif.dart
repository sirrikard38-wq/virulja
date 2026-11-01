import 'dart:typed_data';

/// When and where a photo was taken, as far as the file says.
class ExifInfo {
  const ExifInfo({this.takenAt, this.latitude, this.longitude});

  final DateTime? takenAt;
  final double? latitude;
  final double? longitude;
}

/// Reads the date and the position from a JPEG. Anything missing or damaged
/// simply stays null: a photo without them is still a photo.
ExifInfo readExif(Uint8List bytes) {
  try {
    final tiffStart = _findTiff(bytes);
    if (tiffStart == null) return const ExifInfo();
    return _Tiff(ByteData.sublistView(bytes), tiffStart).read();
  } on RangeError {
    return const ExifInfo();
  }
}

/// When a video was taken, from the `mvhd` box of an MP4 or QuickTime file, which
/// counts seconds from 1904. Null when [bytes] do not hold it.
DateTime? readVideoDate(Uint8List bytes) {
  const name = [0x6D, 0x76, 0x68, 0x64]; // mvhd
  final data = ByteData.sublistView(bytes);
  for (var at = 0; at + 16 <= bytes.length; at++) {
    if (bytes[at] != name[0] ||
        bytes[at + 1] != name[1] ||
        bytes[at + 2] != name[2] ||
        bytes[at + 3] != name[3]) {
      continue;
    }
    final seconds = bytes[at + 4] == 1
        ? data.getUint32(at + 8) * 4294967296 + data.getUint32(at + 12)
        : data.getUint32(at + 8);
    final date = DateTime.utc(1904).add(Duration(seconds: seconds));
    return date.year < 2000 ? null : date;
  }
  return null;
}

/// Where the TIFF block inside the JPEG's Exif segment starts.
int? _findTiff(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var at = 2;
  while (at + 4 <= bytes.length) {
    if (bytes[at] != 0xFF) return null;
    final marker = bytes[at + 1];
    if (marker == 0xDA || marker == 0xD9) return null; // the picture itself
    final length = (bytes[at + 2] << 8) | bytes[at + 3];
    const exifName = [0x45, 0x78, 0x69, 0x66, 0, 0];
    final isExif = marker == 0xE1 &&
        at + 10 <= bytes.length &&
        [for (var i = 0; i < 6; i++) bytes[at + 4 + i] == exifName[i]]
            .every((same) => same);
    if (isExif) return at + 10;
    at += 2 + length;
  }
  return null;
}

class _Tiff {
  _Tiff(this._data, this._start);

  static const _tagExifBlock = 0x8769;
  static const _tagGpsBlock = 0x8825;
  static const _tagDateTime = 0x0132;
  static const _tagDateTimeOriginal = 0x9003;

  final ByteData _data;
  final int _start;
  late final Endian _endian;

  ExifInfo read() {
    final order = _data.getUint16(_start);
    if (order == 0x4949) {
      _endian = Endian.little;
    } else if (order == 0x4D4D) {
      _endian = Endian.big;
    } else {
      return const ExifInfo();
    }
    final main = _entries(_start + _data.getUint32(_start + 4, _endian));
    final exifBlock = main[_tagExifBlock];
    final gpsBlock = main[_tagGpsBlock];

    String? date;
    if (exifBlock != null) {
      final exif = _entries(_start + _value(exifBlock));
      final original = exif[_tagDateTimeOriginal];
      if (original != null) date = _ascii(original);
    }
    if (date == null && main[_tagDateTime] != null) {
      date = _ascii(main[_tagDateTime]!);
    }

    double? latitude, longitude;
    if (gpsBlock != null) {
      final gps = _entries(_start + _value(gpsBlock));
      latitude = _coordinate(gps[1], gps[2], 'S');
      longitude = _coordinate(gps[3], gps[4], 'W');
    }
    return ExifInfo(
      takenAt: date == null ? null : _parseDate(date),
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// tag -> the place of its 12-byte directory entry
  Map<int, int> _entries(int block) {
    final count = _data.getUint16(block, _endian);
    return {
      for (var i = 0; i < count; i++)
        _data.getUint16(block + 2 + i * 12, _endian): block + 2 + i * 12,
    };
  }

  int _value(int entry) => _data.getUint32(entry + 8, _endian);

  String _ascii(int entry) {
    final length = _data.getUint32(entry + 4, _endian);
    final at = length <= 4 ? entry + 8 : _start + _value(entry);
    final codes = <int>[];
    for (var i = 0; i < length; i++) {
      final code = _data.getUint8(at + i);
      if (code == 0) break;
      codes.add(code);
    }
    return String.fromCharCodes(codes);
  }

  double? _coordinate(int? reference, int? value, String negativeSide) {
    if (reference == null || value == null) return null;
    final at = _start + _value(value);
    double part(int index) {
      final top = _data.getUint32(at + index * 8, _endian);
      final bottom = _data.getUint32(at + index * 8 + 4, _endian);
      return bottom == 0 ? 0 : top / bottom;
    }

    final degrees = part(0) + part(1) / 60 + part(2) / 3600;
    return _ascii(reference) == negativeSide ? -degrees : degrees;
  }

  /// `2027:06:12 20:41:05`, kept as the phone's clock showed it.
  DateTime? _parseDate(String text) {
    final match =
        RegExp(r'^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)').firstMatch(text);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
    if (parts[0] == 0 || parts[1] == 0 || parts[2] == 0) return null;
    return DateTime.utc(
        parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }
}
