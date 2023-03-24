import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_talk/src/iot/at_chops_secure_element.dart';
import 'package:at_utils/at_logger.dart';

/// Usage: dart main.dart <cram_secret>
Future<void> main(List<String> args) async {
  final atSign = '@56hurt89';
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    ..hiveStoragePath = 'storage/hive'
    ..namespace = 'wavi'
    ..downloadPath = 'storage/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = 'storage/commitLog'
    ..rootDomain = 'root.atsign.wtf'
    ..fetchOfflineNotifications = true
    ..atKeysFilePath = 'storage/files/@56hurt89_key.atKeys'
    ..useAtChops = true
    ..signingAlgoType=SigningAlgoType.ecc_secp256r1
    ..hashingAlgoType=HashingAlgoType.sha256
    ..authMode=PkamAuthMode.sim
    ..publicKeyId='303037'
  ..cramSecret=args[0]
  ..skipSync=true;
  var logger = AtSignLogger('OnboardSecureElement');
  logger.level = 'INFO';

  AtOnboardingService onboardingService = AtOnboardingServiceImpl(atSign, atOnboardingConfig);
  // create empty keys in atchops. Encryption key pair will be set later on after generation
  onboardingService.atChops = AtChopsSecureElement(AtChopsKeys.create(null, null));
  await onboardingService.onboard();
  await onboardingService.authenticate();
}