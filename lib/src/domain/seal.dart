/// How the seal on a postcard is laid out, and which ink it takes on a photo.
library;

import 'dart:math';

/// How bright a photo must be, from 0 to 255, for dark ink. Anything less takes
/// light ink, which has a shadow to help it on a busy picture.
const int _brightEnough = 158;

/// A place on the seal: a long name with a space goes on two lines, broken where
/// the longer line comes out shortest.
List<String> sealLines(String place) {
  var lines = [place];
  if (place.length < 10) return lines;
  final words = place.split(' ');
  var longest = place.length;
  for (var i = 1; i < words.length; i++) {
    final split = [words.take(i).join(' '), words.skip(i).join(' ')];
    final longer = max(split.first.length, split.last.length);
    if (longer < longest) {
      lines = split;
      longest = longer;
    }
  }
  return lines;
}

/// About how wide [line] is in the display font, in font sizes.
double lettersWide(String line) => line.split('').fold(
    0, (width, letter) => width + (letter == letter.toLowerCase() ? .44 : .72));

/// The part of a photo that lies under the seal: a postcard shows it at 5:4,
/// cutting the same off both sides.
({double x, double y, double width, double height}) sealCorner(int width, int height) {
  final unit = min(width / 5, height / 4);
  final shownWidth = 5 * unit;
  final shownHeight = 4 * unit;
  return (
    x: (width - shownWidth) / 2 + .66 * shownWidth,
    y: (height - shownHeight) / 2 + .03 * shownHeight,
    width: .32 * shownWidth,
    height: .39 * shownHeight,
  );
}

/// Whether [pixels], as red, green, blue and alpha in a row, are bright enough for
/// dark ink.
bool isBright(List<int> pixels) {
  var sum = 0.0;
  for (var i = 0; i < pixels.length; i += 4) {
    sum += .299 * pixels[i] + .587 * pixels[i + 1] + .114 * pixels[i + 2];
  }
  return sum / (pixels.length / 4) >= _brightEnough;
}
