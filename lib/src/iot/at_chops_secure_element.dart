import 'dart:convert';
import 'package:at_talk/src/iot/external_signer.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:at_chops/at_chops.dart';

class AtChopsSecureElement extends AtChopsImpl {
  AtChopsSecureElement(super.atChopsKeys);

  @override
  AtSigningResult sign(AtSigningInput signingInput) {
    final dataHash = sha256.convert(signingInput.data);
    final externalSigner = ExternalSigner();
    externalSigner.init();
    var externalSignature = externalSigner.sign(dataHash.toString());
    if (externalSignature == null) {
      throw Exception('error while computing signature');
    }
    var base64Signature = base64Encode(hex.decode(externalSignature));
    final atSigningMetadata = AtSigningMetaData(signingInput.signingAlgoType,
        signingInput.hashingAlgoType, DateTime.now().toUtc());
    final atSigningResult = AtSigningResult()
      ..result = base64Signature
      ..atSigningMetaData = atSigningMetadata
      ..atSigningResultType = AtSigningResultType.string;
    return atSigningResult;
  }

  @override
  String readPublicKey(String publicKeyId) {
    // return '04269e95122fe3b2d4e2f6aaff810aca12f08be8dd9f1c9a025045e915d81e47e8d886ed34be511e06f2bb7ad220087c73f41942a4186a332aa8ae9a0470852460';
    final externalSigner = ExternalSigner();
    externalSigner.init();
    return externalSigner.getPublicKey(publicKeyId);
  }
}
