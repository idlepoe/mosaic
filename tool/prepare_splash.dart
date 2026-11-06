import 'dart:io';
import 'package:image/image.dart' as img;

/// Package the approved artwork inside Android 12's circular splash safe area.
void main() {
  final source = img.decodePng(
    File('assets/mascot/splash.png').readAsBytesSync(),
  )!;
  final canvas = img.Image(width: 1152, height: 1152, numChannels: 4);
  final artwork = img.copyResize(
    source,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.average,
  );
  img.compositeImage(canvas, artwork, dstX: 320, dstY: 320);
  Directory('assets/native').createSync(recursive: true);
  File(
    'assets/native/splash_android12.png',
  ).writeAsBytesSync(img.encodePng(canvas));
}
