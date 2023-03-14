import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_talk/src/iot/at_chops_secure_element.dart';

Future<void> main() async {
  final atSign = '@snooker10';
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    ..hiveStoragePath = 'storage/hive'
    ..namespace = 'wavi'
    ..downloadPath = 'storage/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = 'storage/commitLog'
    ..rootDomain = 'root.atsign.wtf'
    ..fetchOfflineNotifications = true
    //..atKeysFilePath = 'storage/files/barbara.atKeys'
    ..useAtChops = true
    ..signingAlgoType=SigningAlgoType.ecc_secp256r1
    ..hashingAlgoType=HashingAlgoType.sha256
    ..authMode=PkamAuthMode.sim
    ..publicKeyId='303037'
  ..cramSecret='41bb12d6db2e49aa8942c9601f52fbf82e6809994155e161c099167808f61d3513073a87b64fa625a2918e505aacd54eb3f29ea29b80565077668ba49be8b892';
  AtOnboardingService onboardingService = AtOnboardingServiceImpl(atSign, atOnboardingConfig);
  // create empty keys in atchops. Encryption key pair will be set later on after generation
  onboardingService.atChops = AtChopsSecureElement(AtChopsKeys.create(null, null));
  await onboardingService.onboard();
}