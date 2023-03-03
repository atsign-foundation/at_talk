import 'dart:io';
import 'dart:convert';
import 'dart:async';

// external packages
import 'package:args/args.dart';
import 'package:at_talk/pipe_print.dart';
import 'package:logging/src/level.dart';
import 'package:chalkdart/chalk.dart';

// atPlatform packages
import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

// Local Packages
import 'package:at_talk/home_directory.dart';
import 'package:at_talk/check_file_exists.dart';

void main(List<String> args) async {
  //starting secondary in a zone
  var logger = AtSignLogger('atTalk sender ');
  logger.logger.level = Level.SHOUT;
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
  _logger.logger.level = Level.SHOUT;

  var parser = ArgParser();
// Args
  parser.addOption('key-file',
      abbr: 'k', mandatory: false, help: 'Your @sign\'s atKeys file if not in ~/.atsign/keys/');
  parser.addOption('atsign', abbr: 'a', mandatory: true, help: 'Your atSign');
  parser.addOption('toatsign', abbr: 't', mandatory: true, help: 'Talk to this @sign');
  parser.addOption('root-domain', abbr: 'd', mandatory: false, help: 'Root Domain (defaults to root.atsign.org)');
  parser.addFlag('verbose', abbr: 'v', help: 'More logging');

  // Check the arguments
  dynamic results;
  String atsignFile;

  String fromAtsign = 'unknown';
  String toAtsign = 'unknown';
  String? homeDirectory = getHomeDirectory();
  String nameSpace = 'ai6bh';
  String rootDomain = 'root.atsign.org';
  bool hasTerminal = true;

  try {
    // Arg check
    results = parser.parse(args);
    // Find atSign key file
    fromAtsign = results['atsign'];
    toAtsign = results['toatsign'];

    if (results['root-domain'] != null) {
      rootDomain = results['root-domain'];
    }

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

// Now on to the atPlatform startup
  AtSignLogger.root_level = 'SHOUT';
  if (results['verbose']) {
    _logger.logger.level = Level.INFO;

    AtSignLogger.root_level = 'INFO';
  }

  //onboarding preference builder can be used to set onboardingService parameters
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    ..hiveStoragePath = '$homeDirectory/.$nameSpace/$fromAtsign/storage'
    ..namespace = nameSpace
    ..downloadPath = '$homeDirectory/.$nameSpace/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = '$homeDirectory/.$nameSpace/$fromAtsign/storage/commitLog'
    ..rootDomain = rootDomain
    ..fetchOfflineNotifications = true
    ..atKeysFilePath = atsignFile
    ..useAtChops = true;

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
    ..namespace = nameSpace
    ..metadata = metaData;

  AtOnboardingService onboardingService = AtOnboardingServiceImpl(fromAtsign, atOnboardingConfig);
  bool onboarded = false;
  Duration retryDuration = Duration(seconds: 3);
  while (!onboarded) {
    try {
      stdout.write(chalk.brightBlue('\r\x1b[KConnecting ... '));
      await Future.delayed(Duration(milliseconds: 1000)); // Pause just long enough for the retry to be visible
      onboarded = await onboardingService.authenticate();
    } catch (exception) {
      stdout.write(chalk.brightRed('$exception. Will retry in ${retryDuration.inSeconds} seconds'));
    }
    if (!onboarded) {
      await Future.delayed(retryDuration);
    }
  }
  stdout.writeln(chalk.brightGreen('Connected'));

  // Current atClient is the one which the onboardingService just authenticated
  AtClient atClient = AtClientManager.getInstance().atClient;

  atClient.notificationService.subscribe(regex: 'attalk.$nameSpace@', shouldDecrypt: true).listen(
      ((notification) async {
    String keyAtsign = notification.key;
    keyAtsign = keyAtsign.replaceAll(notification.to + ':', '');
    keyAtsign = keyAtsign.replaceAll('.' + nameSpace + notification.from, '');
    if (keyAtsign == 'attalk') {
      _logger.info('atTalk update received from ' + notification.from + ' notification id : ' + notification.id);
      var talk = notification.value!;
      // Terminal Control
      // '\r\x1b[K' is used to set the cursor back to the beginning of the line then deletes to the end of line
      //
      print(chalk.brightGreen.bold('\r\x1b[K${notification.from}: ') + chalk.brightGreen(talk));

      pipePrint('$fromAtsign: ');
    }
  }),
      onError: (e) => _logger.severe('Notification Failed:' + e.toString()),
      onDone: () => _logger.info('Notification listener stopped'));

  String input = "";
  String buffer = "";
  pipePrint('$fromAtsign: ');

  var lines = stdin.transform(utf8.decoder).transform(const LineSplitter());

  await for (final l in lines) {
    pipePrint('$fromAtsign: ');
    input = l;
    if (input == '/exit') {
      exit(0);
    }
    if (input.startsWith(RegExp('^/@'))) {
      toAtsign = input.replaceFirst(RegExp('^/'), '');
      print('now talking to: $toAtsign');
      input = '';
    }

    if (!(input == "")) {
      if (!(stdin.hasTerminal)) {
        hasTerminal = false;
        buffer = buffer + '\n\r' + input;
      } else {
        hasTerminal = true;
        var success = sendNotification(atClient.notificationService, key, input, _logger);
        if (!await success) {
          print(chalk.brightRed.bold('\r\x1b[KError Sending: ') +
              '"' +
              input +
              '"' +
              ' to $toAtsign - unable to reach the Internet !');
          pipePrint('$fromAtsign: ');
        }
      }
    }
  }

// Send file contents if stdin has no terminal
  if (!(hasTerminal)) {
    var success = sendNotification(atClient.notificationService, key, ' Sending a file' + buffer, _logger);
    if (!await success) {
      print(chalk.brightRed.bold('\r\x1b[KError Sending: ') +
          '"' +
          input +
          '"' +
          ' to $toAtsign - unable to reach the Internet !');
      pipePrint('$fromAtsign: ');
    }
  }

  exit(0);
}

Future<bool> sendNotification(
    NotificationService notificationService, AtKey key, String input, AtSignLogger _logger) async {
  int retry = 0;
  bool success = false;
  while (retry < 3) {
    try {
      await notificationService.notify(NotificationParams.forUpdate(key, value: input), onSuccess: (notification) {
        _logger.info('SUCCESS:' + notification.toString());
      }, onError: (notification) {
        retry++;
        _logger.info('ERROR (retry $retry of 3): "$input"' + notification.toString());
      }, onSentToSecondary: (notification) {
        retry = 4;
        success = true;
        _logger.info('SENT:' + notification.toString());
        // pendingSend--;
      }, waitForFinalDeliveryStatus: false, checkForFinalDeliveryStatus: false);
    } catch (e) {
      _logger.severe(e.toString());
    }
    // back off retries (max 3)
    await Future.delayed(Duration(milliseconds: (500 * (retry))));
  }
  return (success);
}
