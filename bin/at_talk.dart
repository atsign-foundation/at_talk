import 'dart:io';
import 'dart:convert';
import 'dart:async';

// external packages
import 'package:args/args.dart';
import 'package:logging/src/level.dart';
import 'package:chalkdart/chalk.dart';
import 'package:chalkdart/chalk_x11.dart';
import 'package:chalkdart/colorutils.dart';

// @platform packages
import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

// Local Packages
import 'package:at_talk/home_directory.dart';
import 'package:at_talk/check_file_exists.dart';

void main(List<String> args) async {
  //starting secondary in a zone
  var logger = AtSignLogger('atNautel sender ');
  runZonedGuarded(() async {
    await atTalk(args);
  }, (error, stackTrace) {
    logger.severe('Uncaught error: $error');
    logger.severe(stackTrace.toString());
  });
}

Future<void> atTalk(List<String> args) async {
  final AtSignLogger _logger = AtSignLogger(' atTalk ');
  _logger.hierarchicalLoggingEnabled = true;
  _logger.logger.level = Level.WARNING;

  var parser = ArgParser();
// Args
  parser.addOption('key-file',
      abbr: 'k', mandatory: false, help: 'transmitters @sign\'s atKeys file if not in ~/.atsign/keys/');
  parser.addOption('atsign', abbr: 'a', mandatory: true, help: 'Your atSign');
  parser.addOption('toatsign', abbr: 't', mandatory: true, help: 'Talk to this @sign');
  parser.addFlag('verbose', abbr: 'v', help: 'More logging');

  // Check the arguments
  dynamic results;
  String atsignFile;

  String fromAtsign = 'unknown';
  String toAtsign = 'unknown';
  String? homeDirectory = getHomeDirectory();
  String nameSpace = 'ai6bh';

  try {
    // Arg check
    results = parser.parse(args);
    // Find @sign key file
    fromAtsign = results['atsign'];
    toAtsign = results['toatsign'];

    if (results['key-file'] != null) {
      atsignFile = results['key-file'];
    } else {
      atsignFile = '${fromAtsign}_key.atKeys';
      atsignFile = '$homeDirectory/.atsign/keys/$atsignFile';
    }
    // Check atKeyFile selected exists
    if (!await fileExists(atsignFile)) {
      throw ('\n Unable to find .atKeys file : $atsignFile');
    }
  } catch (e) {
    print(parser.usage);
    print(e);
    exit(1);
  }

// Now on to the @platform startup
  AtSignLogger.root_level = 'SHOUT';
  if (results['verbose']) {
    _logger.logger.level = Level.INFO;

    AtSignLogger.root_level = 'INFO';
  }

  //onboarding preference builder can be used to set onboardingService parameters
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    //..qrCodePath = 'etc/qrcode_blueamateurbinding.png'
    ..hiveStoragePath = '$homeDirectory/.$nameSpace/$fromAtsign/storage'
    ..namespace = nameSpace
    ..downloadPath = '$homeDirectory/.$nameSpace/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = '$homeDirectory/.$nameSpace/$fromAtsign/storage/commitLog'
    //..cramSecret = '<your cram secret>';
    ..atKeysFilePath = atsignFile;

  AtOnboardingService onboardingService = AtOnboardingServiceImpl(fromAtsign, atOnboardingConfig);

  await onboardingService.authenticate();

  AtClient? atClient = await onboardingService.getAtClient();

  // var atClient = await onboardingService.getAtClient();

  AtClientManager atClientManager = AtClientManager.getInstance();

  NotificationService notificationService = atClientManager.notificationService;

  bool syncComplete = false;
  void onSyncDone(syncResult) {
    _logger.info("syncResult.syncStatus: ${syncResult.syncStatus}");
    _logger.info("syncResult.lastSyncedOn ${syncResult.lastSyncedOn}");
    syncComplete = true;
  }

  // Wait for initial sync to complete
  _logger.info("Waiting for initial sync");
  syncComplete = false;
  atClientManager.syncService.sync(onDone: onSyncDone);
  while (!syncComplete) {
    await Future.delayed(Duration(milliseconds: 100));
  }

// Keep an eye on connectivity and report failures if we see them
  ConnectivityListener().subscribe().listen((isConnected) {
    if (isConnected) {
      _logger.warning('connection available');
    } else {
      _logger.warning('connection lost');
    }
  });

  notificationService.subscribe(regex: 'attalk.$nameSpace@', shouldDecrypt: true).listen(((notification) async {
    String keyAtsign = notification.key;
    //Uint8List buffer;
    keyAtsign = keyAtsign.replaceAll(notification.to + ':', '');
    keyAtsign = keyAtsign.replaceAll('.' + nameSpace + notification.from, '');
    if (keyAtsign == 'attalk') {
      _logger.info('atTalk update recieved from ' + notification.from + ' notification id : ' + notification.id);
      var talk = notification.value!;
      print(chalk.brightGreen.dim('\r$toAtsign: ') + chalk.brightGreen(talk));
      stdout.write(chalk.brightWhite.dim('$fromAtsign: '));
    }
  }),
      onError: (e) => _logger.severe('Notification Failed:' + e.toString()),
      onDone: () => _logger.info('Notification listener stopped'));
  String input = "";
  stdout.write(chalk.brightWhite.dim('$fromAtsign: '));

  var lines = stdin.transform(utf8.decoder).transform(const LineSplitter());

  await for (final l in lines) {
    input = l;
    if (input == '/exit') {
      exit(0);
    }

    stdout.write(chalk.brightWhite.dim('$fromAtsign: '));

    var metaData = Metadata()
      ..isPublic = false
      ..isEncrypted = true
      ..namespaceAware = true
      ..ttr = -1
      ..ttl = 10000;

    var key = AtKey()
      ..key = 'attalk'
      ..sharedBy = fromAtsign
      ..sharedWith = toAtsign
      ..namespace = atClient?.getPreferences()?.namespace
      ..metadata = metaData;
    if (! (input == "")) {
      try {
        await notificationService.notify(NotificationParams.forUpdate(key, value: input), onSuccess: (notification) {
          _logger.info('SUCCESS:' + notification.toString());
        }, onError: (notification) {
          _logger.info('ERROR:' + notification.toString());
        });
      } catch (e) {
        _logger.severe(e.toString());
      }
    }
  }
}
