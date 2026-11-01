import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The two standards a phone's push service asks for: the message is encrypted
/// for that one phone (RFC 8291) and the sender proves who it is (RFC 8292).

final ECDomainParameters _curve = ECCurve_secp256r1();

String toBase64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List fromBase64Url(String text) => base64Url.decode(base64Url.normalize(text));

BigInt _number(List<int> bytes) =>
    bytes.fold(BigInt.zero, (sum, byte) => (sum << 8) | BigInt.from(byte));

Uint8List _bytes(BigInt number) {
  final out = Uint8List(32);
  var rest = number;
  for (var i = 31; i >= 0; i--) {
    out[i] = (rest & BigInt.from(255)).toInt();
    rest >>= 8;
  }
  return out;
}

Uint8List newPrivateKey() {
  final random = Random.secure();
  while (true) {
    final bytes = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
    final number = _number(bytes);
    if (number > BigInt.zero && number < _curve.n) return bytes;
  }
}

Uint8List publicKeyOf(Uint8List privateKey) =>
    (_curve.G * _number(privateKey))!.getEncoded(false);

Uint8List _hmac(List<int> key, List<int> data) {
  final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(Uint8List.fromList(key)));
  return mac.process(Uint8List.fromList(data));
}

/// HKDF for at most 32 bytes, all this needs.
Uint8List _hkdf(List<int> salt, List<int> secret, List<int> info, int length) =>
    Uint8List.sublistView(_hmac(_hmac(salt, secret), [...info, 1]), 0, length);

/// [message] encrypted for the phone with [phoneKey] and [authSecret].
/// [privateKey] and [salt] are fresh for each message; tests can fix them.
Uint8List encryptPush(
  List<int> message,
  Uint8List phoneKey,
  Uint8List authSecret, {
  Uint8List? privateKey,
  Uint8List? salt,
}) {
  const recordSize = 4096;
  final own = privateKey ?? newPrivateKey();
  final ownPublic = publicKeyOf(own);
  final random = Random.secure();
  final nonceSalt =
      salt ?? Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));

  final agreement = ECDHBasicAgreement()
    ..init(ECPrivateKey(_number(own), _curve));
  final shared = _bytes(
      agreement.calculateAgreement(ECPublicKey(_curve.curve.decodePoint(phoneKey), _curve)));

  final keyInfo = [...ascii.encode('WebPush: info'), 0, ...phoneKey, ...ownPublic];
  final secret = _hkdf(authSecret, shared, keyInfo, 32);
  final key = _hkdf(nonceSalt, secret, [...ascii.encode('Content-Encoding: aes128gcm'), 0], 16);
  final nonce = _hkdf(nonceSalt, secret, [...ascii.encode('Content-Encoding: nonce'), 0], 12);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  final sealed = cipher.process(Uint8List.fromList([...message, 2]));

  final size = ByteData(4)..setUint32(0, recordSize);
  return Uint8List.fromList([
    ...nonceSalt,
    ...size.buffer.asUint8List(),
    ownPublic.length,
    ...ownPublic,
    ...sealed,
  ]);
}

/// The `Authorization` header for a message to [endpoint].
String vapidHeader(String endpoint, Uint8List privateKey, String contact, DateTime now) {
  final uri = Uri.parse(endpoint);
  final expires = now.add(const Duration(hours: 12)).millisecondsSinceEpoch ~/ 1000;
  String part(Object json) => toBase64Url(utf8.encode(jsonEncode(json)));
  final unsigned = '${part({'typ': 'JWT', 'alg': 'ES256'})}.'
      '${part({'aud': uri.origin, 'exp': expires, 'sub': contact})}';
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(_number(privateKey), _curve)));
  final signature =
      signer.generateSignature(Uint8List.fromList(ascii.encode(unsigned))) as ECSignature;
  final token = '$unsigned.${toBase64Url([..._bytes(signature.r), ..._bytes(signature.s)])}';
  return 'vapid t=$token, k=${toBase64Url(publicKeyOf(privateKey))}';
}

/// True when [header] carries a valid signature: what a push service checks.
bool vapidIsValid(String header, Uint8List publicKey) {
  final token = header.substring('vapid t='.length, header.indexOf(','));
  final at = token.lastIndexOf('.');
  final signature = fromBase64Url(token.substring(at + 1));
  final verifier = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter<ECPublicKey>(
        ECPublicKey(_curve.curve.decodePoint(publicKey), _curve)));
  return verifier.verifySignature(
    Uint8List.fromList(ascii.encode(token.substring(0, at))),
    ECSignature(_number(signature.sublist(0, 32)), _number(signature.sublist(32))),
  );
}
