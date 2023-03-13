import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_talk/src/iot/at_chops_secure_element.dart';

Future<void> main() async {
  final atSign = '@barbara';
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    ..hiveStoragePath = 'storage/hive'
    ..namespace = 'wavi'
    ..downloadPath = 'storage/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = 'storage/commitLog'
    ..rootDomain = 'vip.ve.atsign.zone'
    ..fetchOfflineNotifications = true
    //..atKeysFilePath = 'storage/files/barbara.atKeys'
    ..useAtChops = true
    ..signingAlgoType=SigningAlgoType.ecc_secp256r1
    ..hashingAlgoType=HashingAlgoType.sha256
    ..authMode=PkamAuthMode.sim
    ..publicKeyId='303037'
  ..cramSecret='b43edaa255f738c763c2c79df4d49a4173b02c132e164b77650383fffe16f045ef8065c2ec05df8f4ae3475e04e83c7c99e96f52de9c4d1a915b67d24f590c99';
  AtOnboardingService onboardingService = AtOnboardingServiceImpl(atSign, atOnboardingConfig);
  // create empty keys in atchops. Encryption key pair will be set later on after generation
  onboardingService.atChops = AtChopsSecureElement(AtChopsKeys.create(null, null));
  await onboardingService.onboard();
}