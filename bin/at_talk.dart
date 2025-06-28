import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:at_talk/tui_chat.dart';

// external packages
import 'package:args/args.dart';
import 'package:at_talk/pipe_print.dart';
import 'package:at_talk/service_factories.dart';
import 'package:logging/src/level.dart';
import 'package:chalkdart/chalk.dart';
import 'package:uuid/uuid.dart';

// atPlatform packages
import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

// Local Packages
import 'package:at_talk/home_directory.dart';
import 'package:at_talk/check_file_exists.dart';
import 'package:version/version.dart';

const String digits = '0123456789';
final RegExp generateCommandRegEx = RegExp(r'^/gen \d+$');

void main(List<String> args) async {
  //starting secondary in a zone
  var logger = AtSignLogger('atTalk sender ');
  logger.logger.level = Level.SHOUT;
  await runZonedGuarded(() async {
    await atTalk(args);
  }, (error, stackTrace) {
    logger.severe('Uncaught error: $error');
    logger.severe(stackTrace.toString());
  });
}

Future<void> atTalk(List<String> args) async {
  final AtSignLogger logger = AtSignLogger(' atTalk ');
  logger.hierarchicalLoggingEnabled = true;
  logger.logger.level = Level.SHOUT;

  var parser = ArgParser();
// Args
  parser.addOption('key-file',
      abbr: 'k',
      mandatory: false,
      help: 'Your atSign\'s atKeys file if not in ~/.atsign/keys/');
  parser.addOption('atsign', abbr: 'a', mandatory: true, help: 'Your atSign');
  parser.addOption('toatsign',
      abbr: 't', mandatory: true, help: 'Talk to this atSign');
  parser.addOption('root-domain',
      abbr: 'd',
      mandatory: false,
      help: 'Root Domain (defaults to root.atsign.org)');
  parser.addOption('namespace',
      abbr: 'n', mandatory: false, help: 'Namespace (defaults to ai6bh)');
  parser.addOption('message',
      abbr: 'm', mandatory: false, help: 'send a message then exit');
  parser.addFlag('verbose', abbr: 'v', help: 'More logging', negatable: false);
  parser.addFlag('never-sync',
      help: 'Completely disable sync', negatable: false);

  // Check the arguments
  dynamic parsedArgs;
  String atsignFile;

  String fromAtsign = 'unknown';
  String toAtsign = 'unknown';
  String? homeDirectory = getHomeDirectory();
  String nameSpace = 'ai6bh';
  String rootDomain = 'root.atsign.org';
  String? message;
  bool hasTerminal = true;

  try {
    // Arg check
    parsedArgs = parser.parse(args);
    // Find atSign key file
    fromAtsign = parsedArgs['atsign'];
    toAtsign = parsedArgs['toatsign'];

    if (parsedArgs['root-domain'] != null) {
      rootDomain = parsedArgs['root-domain'];
    }

    if (parsedArgs['namespace'] != null) {
      nameSpace = parsedArgs['namespace'];
    }
    if (parsedArgs['message'] != null) {
      message = parsedArgs['message'];
    }

    if (parsedArgs['key-file'] != null) {
      atsignFile = parsedArgs['key-file'];
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

  AtServiceFactory? atServiceFactory;
  if (parsedArgs['never-sync']) {
    stdout.writeln(
        chalk.brightBlue('Creating ServiceFactoryWithNoOpSyncService'));
    atServiceFactory = ServiceFactoryWithNoOpSyncService();
  }

// Now on to the atPlatform startup
  AtSignLogger.root_level = 'SHOUT';
  if (parsedArgs['verbose']) {
    logger.logger.level = Level.INFO;

    AtSignLogger.root_level = 'INFO';
  }

  Uuid uuid = Uuid();
  //onboarding preference builder can be used to set onboardingService parameters
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    ..hiveStoragePath = '$homeDirectory/.$nameSpace/$fromAtsign/$uuid/storage'
    ..namespace = nameSpace
    ..downloadPath = '$homeDirectory/.$nameSpace/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = '$homeDirectory/.$nameSpace/$fromAtsign/$uuid/storage/commitLog'
    ..rootDomain = rootDomain
    ..fetchOfflineNotifications = true
    ..atKeysFilePath = atsignFile
    ..atProtocolEmitted = Version(2, 0, 0);

  var metaData = Metadata()
    ..isPublic = false
    ..isEncrypted = true
    ..namespaceAware = true;

  var key = AtKey()
    ..key = 'attalk'
    ..sharedBy = fromAtsign
    ..sharedWith = toAtsign
    ..namespace = nameSpace
    ..metadata = metaData;

  AtOnboardingService onboardingService = AtOnboardingServiceImpl(
      fromAtsign, atOnboardingConfig,
      atServiceFactory: atServiceFactory);
  bool onboarded = false;
  Duration retryDuration = Duration(seconds: 3);
  while (!onboarded) {
    try {
      stdout.write(chalk.brightBlue('\r\x1b[KConnecting ... '));
      await Future.delayed(Duration(
          milliseconds:
              1000)); // Pause just long enough for the retry to be visible
      onboarded = await onboardingService.authenticate();
    } catch (exception) {
      stdout.write(chalk.brightRed(
          '$exception. Will retry in ${retryDuration.inSeconds} seconds'));
    }
    if (!onboarded) {
      await Future.delayed(retryDuration);
    }
  }
  stdout.writeln(chalk.brightGreen('Connected'));

  // Current atClient is the one which the onboardingService just authenticated
  AtClient atClient = AtClientManager.getInstance().atClient;

  // Start TUI chat app
  final tui = TuiChatApp(fromAtsign);
  tui.addSession(toAtsign);

  // Listen for incoming messages
  atClient.notificationService
      .subscribe(regex: 'attalk.$nameSpace@', shouldDecrypt: true)
      .listen(((notification) async {
    try {
      final value = notification.value;
      if (value == null) return;
      final data = jsonDecode(value);
      if (data is! Map) return;
      final group = (data['group'] as List).map((e) => e.toString()).toList();
      final from = data['from'] as String? ?? notification.from;
      final msg = data['msg'] as String? ?? value;
      // Exclude my own atSign from the group, but always include the creator (from)
      final filteredGroup = group.where((a) => a != fromAtsign).toSet().toList();
      if (!filteredGroup.contains(from)) filteredGroup.add(from);
      filteredGroup.sort();
      final groupKey = filteredGroup.join(',');
      tui.addSession(group.length > 1 ? groupKey : from, filteredGroup);
      tui.addMessage(group.length > 1 ? groupKey : from, msg, incoming: true);
      tui.draw();
    } catch (e) {
      // fallback: treat as plain message
      tui.addMessage(notification.from, notification.value ?? '', incoming: true);
      tui.draw();
    }
  }),
          onError: (e) => logger.severe('Notification Failed:$e'),
          onDone: () => logger.info('Notification listener stopped'));

  // Outgoing message handler
  tui.onSend = (String sessionId, String message) async {
    final session = tui.sessions[sessionId];
    if (session == null) return;
    // Always send to all group members except self, using the full group list as the group key
    final group = session.participants.toSet().toList()..sort();
    final groupKey = group.join(',');
    for (final atSign in group) {
      if (atSign == fromAtsign) continue;
      var metaData = Metadata()
        ..isPublic = false
        ..isEncrypted = true
        ..namespaceAware = true;
      var key = AtKey()
        ..key = 'attalk'
        ..sharedBy = fromAtsign
        ..sharedWith = atSign
        ..namespace = nameSpace
        ..metadata = metaData;
      var payload = jsonEncode({
        'group': group,
        'from': fromAtsign,
        'msg': message
      });
      var success = await sendNotification(atClient.notificationService, key, payload, logger);
      if (!success) {
        tui.addMessage(groupKey, '[Error: Unable to send to $atSign]', incoming: true);
        tui.draw();
      }
    }
  };

  // Run the TUI
  await tui.run();
  exit(0);
}

Future<bool> sendNotification(NotificationService notificationService,
    AtKey key, String input, AtSignLogger logger) async {
  bool success = false;

  // back off retries (max 3)
  for (int retry = 0; retry < 3; retry++) {
    try {
      NotificationResult result = await notificationService.notify(
          NotificationParams.forUpdate(key, value: input),
          waitForFinalDeliveryStatus: false,
          checkForFinalDeliveryStatus: false);
      if (result.atClientException != null) {
        logger.warning(result.atClientException);
        retry++;
        await Future.delayed(Duration(milliseconds: (500 * (retry))));
      } else {
        success = true;
        break;
      }
    } catch (e) {
      logger.warning(e);
    }
  }
  return (success);
}
