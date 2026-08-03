import 'package:flutter_test/flutter_test.dart';
import 'package:smartdolphin_vpn/services/remote/support_chat_api.dart';

void main() {
  test('mobile image formats retain image MIME types', () {
    expect(supportMediaTypeForPath('camera.HEIC').mimeType, 'image/heic');
    expect(supportMediaTypeForPath('photo.heif').mimeType, 'image/heif');
    expect(supportMediaTypeForPath('photo.webp').mimeType, 'image/webp');
  });

  test('video containers are not mislabeled as MP4', () {
    expect(supportMediaTypeForPath('camera.mov').mimeType, 'video/quicktime');
    expect(supportMediaTypeForPath('clip.webm').mimeType, 'video/webm');
    expect(supportMediaTypeForPath('clip.mkv').mimeType, 'video/x-matroska');
  });
}
