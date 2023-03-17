import 'dart:convert';
import 'dart:typed_data';
import 'package:at_talk/src/iot/external_signer.dart';
import 'package:crypto/crypto.dart';
import 'package:at_chops/at_chops.dart';

class AtChopsSecureElement extends AtChopsImpl {
  AtChopsSecureElement(AtChopsKeys atChopsKeys) : super(atChopsKeys);

  @override
  AtSigningResult sign(AtSigningInput signingInput) {
    final dataHash = sha256.convert(_getBytes(signingInput.data));
    final externalSigner = ExternalSigner();
    externalSigner.init();
    var externalSignature = externalSigner.sign(dataHash.toString());
    if (externalSignature == null) {
      throw Exception('error while computing signature');
    }
    var base64Signature = base64Encode(externalSignature.codeUnits);
    final atSigningMetadata = AtSigningMetaData(signingInput.signingAlgoType,
        signingInput.hashingAlgoType, DateTime.now().toUtc());
    final atSigningResult = AtSigningResult()
      ..result = base64Signature
      ..atSigningMetaData = atSigningMetadata
      ..atSigningResultType = AtSigningResultType.string;
    return atSigningResult;
  }

  Uint8List _getBytes(dynamic data) {
    if (data is String) {
      return utf8.encode(data) as Uint8List;
    } else if (data is Uint8List) {
      return data;
    } else {
      throw Exception('Unrecognized type of data: $data');
    }
  }

  @override
  String readPublicKey(String publicKeyId) {
    // return '04269e95122fe3b2d4e2f6aaff810aca12f08be8dd9f1c9a025045e915d81e47e8d886ed34be511e06f2bb7ad220087c73f41942a4186a332aa8ae9a0470852460';
    final externalSigner = ExternalSigner();
    externalSigner.init();
    return externalSigner.getPublicKey(publicKeyId).toLowerCase();
  }
}
