import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:at_talk/tui_chat.dart';

// external packages
import 'package:args/args.dart';
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
  bool hasTerminal = stdin.hasTerminal;

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

  String uuid = Uuid().v4();
  String instanceId = Uuid().v4(); // Unique ID for this app instance
  //onboarding preference builder can be used to set onboardingService parameters
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    ..hiveStoragePath = '$homeDirectory/.$nameSpace/$fromAtsign/$uuid/storage'
    ..namespace = nameSpace
    ..downloadPath = '$homeDirectory/.$nameSpace/$uuid/files'
    ..isLocalStoreRequired = true
    ..monitorHeartbeatInterval = Duration(seconds: 5)
    ..commitLogPath =
        '$homeDirectory/.$nameSpace/$fromAtsign/$uuid/storage/commitLog'
    ..rootDomain = rootDomain
    ..fetchOfflineNotifications = true
    ..atKeysFilePath = atsignFile
    ..atProtocolEmitted = Version(2, 0, 0);

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

  // If no terminal, read from stdin (pipe mode)
  if (!hasTerminal && message == null) {
    try {
      // Read all input from stdin
      List<String> lines = [];
      await for (final line
          in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
        lines.add(line);
      }
      if (lines.isNotEmpty) {
        message = "file sent\n" + lines.join('\n');
      }
    } catch (e) {
      stderr.writeln('Error reading from stdin: $e');
      exit(1);
    }
  }

  // If -m is used OR pipe input, send message(s) and exit cleanly
  if (message != null && message.isNotEmpty) {
    // Support comma-separated list for -t
    var recipients = toAtsign
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    final isGroupMessage = recipients.length > 1;
    final group = recipients.toSet().toList()..sort();

    // For multi-instance support, we need to send to ourselves too
    final allRecipients = recipients.toSet().toList()..add(fromAtsign);

    bool allSuccess = true;
    for (final atSign in allRecipients) {
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
        'msg': message,
        'instanceId': instanceId,
        'isGroup': isGroupMessage
      });
      var success = await sendNotification(
          atClient.notificationService, key, payload, logger);
      if (!success) {
        if (hasTerminal) {
          stdout.writeln(chalk.red('[Error: Unable to send to $atSign]'));
        } else {
          stderr.writeln('[Error: Unable to send to $atSign]');
        }
        allSuccess = false;
      } else {
        if (!hasTerminal) {
          stderr.writeln('Message sent to $atSign');
        }
      }
    }

    if (hasTerminal) {
      stdout.writeln(chalk.green('Message sent.'));
    } else {
      if (allSuccess) {
        stderr.writeln('All messages sent successfully.');
        exit(0);
      } else {
        stderr.writeln('Some messages failed to send.');
        exit(1);
      }
    }
    exit(allSuccess ? 0 : 1);
  }

  // Only start TUI if we have a terminal
  if (!hasTerminal) {
    stderr.writeln('No terminal available and no message to send');
    exit(1);
  }

  // Start TUI chat app
  final tui = TuiChatApp(fromAtsign);

  // If -m is not used, support group chat creation from comma-separated -t
  List<String> participants = toAtsign
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
  if (participants.length > 1) {
    // Group chat: include myself in the participants list for consistency
    participants.add(fromAtsign);
    final allParticipants = participants.toSet().toList()..sort();
    final groupKey = allParticipants.join(',');
    tui.addSession(groupKey, allParticipants);
    tui.switchSession(groupKey);
  } else {
    // Individual chat: include both participants for consistency
    final individualParticipants =
        [fromAtsign, participants[0]].toSet().toList()..sort();
    final sessionKey = participants[0]; // Use the other person's atSign as key
    tui.addSession(sessionKey, individualParticipants);
    tui.switchSession(sessionKey);
  }

  // Listen for incoming messages
  atClient.notificationService
      .subscribe(regex: 'attalk.$nameSpace@', shouldDecrypt: true)
      .listen(((notification) async {
    try {
      final value = notification.value;
      if (value == null) return;
      final data = jsonDecode(value);
      if (data is! Map) return;

      // Check if this is a group rename notification
      if (data['type'] == 'groupRename') {
        final group = (data['group'] as List).map((e) => e.toString()).toList();
        final newGroupName = data['groupName'] as String?;
        final sessionParticipants = group.toSet().toList()..sort();
        final sessionKey = sessionParticipants.join(',');

        // Update the group name
        tui.addSession(sessionKey, sessionParticipants, newGroupName);
        final displayName =
            newGroupName?.isNotEmpty == true ? newGroupName! : 'Unnamed Group';
        tui.addMessage(sessionKey, '[Group renamed to "$displayName"]',
            incoming: true);
        tui.draw();
        return;
      }

      // Check if this is a group membership change notification
      if (data['type'] == 'groupMembershipChange') {
        final group = (data['group'] as List).map((e) => e.toString()).toList();
        final groupName = data['groupName'] as String?;
        final sessionParticipants = group.toSet().toList()..sort();

        // Try to find existing session with different participant set
        String? existingSessionKey =
            tui.findSessionWithParticipants(sessionParticipants);

        if (existingSessionKey == null) {
          // Look for a session that has some of the same participants but different membership
          // BUT only migrate existing sessions under specific conditions to avoid overwriting individual chats
          for (var entry in tui.sessions.entries) {
            var entryParticipants = entry.value.participants.toSet();
            var newParticipants = sessionParticipants.toSet();

            // Only consider migrating if:
            // 1. The existing session is already a group (3+ participants), OR
            // 2. The existing session is an individual chat (2 participants) AND the new session is also individual with same participants
            bool shouldMigrate = false;

            if (entryParticipants.length >= 3) {
              // Existing session is already a group - safe to migrate if there's significant overlap
              shouldMigrate =
                  entryParticipants.intersection(newParticipants).length >= 2 &&
                      entryParticipants.contains(fromAtsign);
            } else if (entryParticipants.length == 2 &&
                newParticipants.length == 2) {
              // Both are individual chats - only migrate if they have exactly the same participants
              shouldMigrate =
                  entryParticipants.difference(newParticipants).isEmpty &&
                      newParticipants.difference(entryParticipants).isEmpty;
            }
            // Don't migrate individual chats (2 participants) to group chats (3+ participants)

            if (shouldMigrate) {
              existingSessionKey = entry.key;
              break;
            }
          }
        }

        if (existingSessionKey != null) {
          // Update existing session
          var session = tui.sessions[existingSessionKey]!;
          var oldParticipants = session.participants.toSet();
          var newParticipants = sessionParticipants.toSet();

          // Generate new session key
          var newSessionKey = tui.generateSessionKey(sessionParticipants);

          if (newSessionKey != existingSessionKey) {
            // Need to migrate session
            var messages = session.messages.toList();
            tui.addSession(newSessionKey, sessionParticipants, groupName);
            tui.sessions[newSessionKey]!.messages.addAll(messages);

            // Remove old session
            tui.sessions.remove(existingSessionKey);

            // Update active session if it was the migrated one
            if (tui.activeSession == existingSessionKey) {
              tui.activeSession = newSessionKey;
              tui.windowOffset = tui.sessionList.indexOf(newSessionKey);
            }
          } else {
            // Same key, just update participants and group name
            session.participants.clear();
            session.participants.addAll(sessionParticipants);
            session.groupName = groupName;
          }

          // Show what changed
          var added = newParticipants.difference(oldParticipants);
          var removed = oldParticipants.difference(newParticipants);

          for (var participant in added) {
            if (participant != fromAtsign) {
              tui.addMessage(tui.activeSession ?? newSessionKey,
                  '[${participant} joined the group]',
                  incoming: true);
            }
          }
          for (var participant in removed) {
            if (participant != fromAtsign) {
              tui.addMessage(tui.activeSession ?? newSessionKey,
                  '[${participant} left the group]',
                  incoming: true);
            }
          }
        } else {
          // Create new session
          var newSessionKey = tui.generateSessionKey(sessionParticipants);
          tui.addSession(newSessionKey, sessionParticipants, groupName);
        }

        tui.draw();
        return;
      }

      final group = (data['group'] as List).map((e) => e.toString()).toList();
      final from = data['from'] as String? ?? notification.from;
      final msg = data['msg'] as String? ?? value;
      final messageInstanceId = data['instanceId'] as String?;
      final isGroup = data['isGroup'] as bool? ?? false;
      final groupName = data['groupName'] as String?;

      // Skip messages from this same app instance to avoid duplicates
      // But allow messages to self from different instances
      if (from == fromAtsign && messageInstanceId == instanceId) return;

      // Use the isGroup flag to determine session handling
      String sessionKey;
      List<String> sessionParticipants;

      if (isGroup) {
        // Group chat: use all participants (including myself) for consistency
        sessionParticipants = group.toSet().toList()..sort();
        sessionKey = sessionParticipants.join(',');
      } else {
        // Individual chat: use all participants for consistency
        sessionParticipants = group.toSet().toList()..sort();

        if (sessionParticipants.length == 2 &&
            sessionParticipants.contains(fromAtsign)) {
          // Standard individual chat: use the other person's atSign as the key
          sessionKey = sessionParticipants.firstWhere((p) => p != fromAtsign);
        } else if (sessionParticipants.length == 1 &&
            sessionParticipants[0] == fromAtsign) {
          // Self-chat session
          sessionKey = fromAtsign;
        } else {
          // Fallback: use the sorted participant list
          sessionKey = sessionParticipants.join(',');
        }
      }

      // Try to find existing session with same participants first
      // This helps avoid duplicate sessions when group membership changes
      String? existingSessionKey =
          tui.findSessionWithParticipants(sessionParticipants);
      if (existingSessionKey != null) {
        sessionKey = existingSessionKey;
      } else {
        // If no exact match, look for a session that could be an updated version
        // This handles cases where participant lists have changed
        // BUT only migrate existing sessions under specific conditions to avoid overwriting individual chats
        for (var entry in tui.sessions.entries) {
          var entryParticipants = entry.value.participants.toSet();
          var newParticipants = sessionParticipants.toSet();

          // Only consider migrating if:
          // 1. The existing session is already a group (3+ participants), OR
          // 2. The existing session is an individual chat (2 participants) AND the new session is also individual with same participants
          bool shouldMigrate = false;

          if (entryParticipants.length >= 3) {
            // Existing session is already a group - safe to migrate if there's significant overlap
            shouldMigrate =
                entryParticipants.intersection(newParticipants).length >= 2 &&
                    entryParticipants.contains(fromAtsign) &&
                    newParticipants.contains(fromAtsign);
          } else if (entryParticipants.length == 2 &&
              newParticipants.length == 2) {
            // Both are individual chats - only migrate if they have exactly the same participants
            shouldMigrate =
                entryParticipants.difference(newParticipants).isEmpty &&
                    newParticipants.difference(entryParticipants).isEmpty;
          }
          // Don't migrate individual chats (2 participants) to group chats (3+ participants)

          if (shouldMigrate) {
            // Update the existing session with new participant list
            var session = entry.value;
            session.participants.clear();
            session.participants.addAll(sessionParticipants);

            // Generate correct session key for the updated participant list
            var correctKey = tui.generateSessionKey(sessionParticipants);
            if (correctKey != entry.key) {
              // Need to migrate to correct key
              var messages = session.messages.toList();
              var groupName = session.groupName;

              tui.addSession(correctKey, sessionParticipants, groupName);
              tui.sessions[correctKey]!.messages.addAll(messages);

              // Remove old session
              tui.sessions.remove(entry.key);

              // Update active session if needed
              if (tui.activeSession == entry.key) {
                tui.activeSession = correctKey;
                tui.windowOffset = tui.sessionList.indexOf(correctKey);
              }

              sessionKey = correctKey;
            } else {
              sessionKey = entry.key;
            }
            break;
          }
        }
      }

      tui.addSession(sessionKey, sessionParticipants, groupName);
      tui.addMessage(
        sessionKey,
        msg,
        incoming: true,
        sender: (from == fromAtsign)
            ? null
            : from, // Use null for own messages to show "me:"
      );
      tui.draw();
    } catch (e) {
      // Skip messages from this same app instance in fallback case too
      if (notification.from == fromAtsign) return;

      // fallback: treat as plain message
      tui.addMessage(notification.from, notification.value ?? '',
          incoming: true);
      tui.draw();
    }
  }),
          onError: (e) => logger.severe('Notification Failed:$e'),
          onDone: () => logger.info('Notification listener stopped'));

  // Outgoing message handler
  tui.onSend = (String sessionId, String message) async {
    final session = tui.sessions[sessionId];
    if (session == null) return;

    // Determine if this is a group chat or individual chat
    // Individual chats have exactly 2 participants (sender and receiver)
    // Group chats have 3 or more participants
    final isGroupChat = session.participants.length > 2;

    List<String> recipients;
    List<String> groupForMessage;

    if (isGroupChat) {
      // Group chat: send to all participants (including self for multi-instance support)
      recipients = session.participants.toSet().toList()..sort();
      groupForMessage =
          recipients; // Include all participants in the message group
    } else {
      // Individual chat: send to the other person AND to myself for multi-instance support
      recipients = session.participants.toSet().toList()
        ..sort(); // includes both sender and receiver
      groupForMessage = session.participants.toSet().toList()
        ..sort(); // Include all participants for consistency
    }

    for (final atSign in recipients) {
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
        'group': groupForMessage,
        'from': fromAtsign,
        'msg': message,
        'instanceId': instanceId,
        'isGroup': isGroupChat,
        'groupName': session.groupName
      });
      var success = await sendNotification(
          atClient.notificationService, key, payload, logger);
      if (!success) {
        tui.addMessage(sessionId, '[Error: Unable to send to $atSign]',
            incoming: true);
        tui.draw();
      }
    }
  };

  // Group rename handler
  tui.onGroupRename = (String sessionId, String newGroupName) async {
    final session = tui.sessions[sessionId];
    if (session == null) return;

    for (final atSign in session.participants) {
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
        'type': 'groupRename',
        'group': session.participants,
        'from': fromAtsign,
        'groupName': newGroupName,
        'instanceId': instanceId,
      });
      await sendNotification(
          atClient.notificationService, key, payload, logger);
    }
  };

  // Group membership change handler
  tui.onGroupMembershipChange =
      (String sessionId, List<String> participants, String? groupName) async {
    final session = tui.sessions[sessionId];
    if (session == null) return;

    for (final atSign in participants) {
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
        'type': 'groupMembershipChange',
        'group': participants,
        'from': fromAtsign,
        'groupName': groupName,
        'instanceId': instanceId,
      });
      await sendNotification(
          atClient.notificationService, key, payload, logger);
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
          NotificationParams.forUpdate(key,
              value: input, notificationExpiry: Duration(days: 1)),
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
