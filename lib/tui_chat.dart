import 'package:chalkdart/chalk.dart';
import 'dart:io';
import 'dart:async';

class ChatSession {
  final String id;
  final List<String> participants;
  String? groupName; // New field for group names
  final List<String> messages = [];
  int scrollOffset = 0;
  int unreadCount = 0;
  ChatSession(this.id, this.participants, {this.groupName});

  // Get display name for the session
  String getDisplayName(String myAtSign) {
    if (groupName != null && groupName!.isNotEmpty) {
      return groupName!;
    }

    // For individual chats (2 participants including me), show only the other person
    if (participants.length == 2 && participants.contains(myAtSign)) {
      return participants.firstWhere((p) => p != myAtSign);
    }

    // For group chats or other cases, show all participants except me
    var others = participants.where((p) => p != myAtSign).toList();
    return others.isEmpty ? participants.join(', ') : others.join(', ');
  }
}

class TuiChatApp {
  final String myAtSign;
  final Map<String, ChatSession> sessions = {};
  String? activeSession;
  void Function(String sessionId, String message)? onSend;
  void Function(String sessionId, String newGroupName)?
      onGroupRename; // New callback for group renames
  int windowOffset = 0;
  int windowSize = 1;
  List<String> get sessionList => sessions.keys.toList();
  String inputBuffer = '';
  int inputCursorPos = 0;
  int inputScrollOffset = 0;
  bool redrawRequested = false;
  bool showHelpHint = true;

  // State for group name input
  bool _waitingForGroupName = false;
  List<String>? _pendingParticipants;
  String? _pendingSessionKey;

  TuiChatApp(this.myAtSign);

  void addSession(String id, [List<String>? participants, String? groupName]) {
    if (!sessions.containsKey(id)) {
      sessions[id] =
          ChatSession(id, participants ?? [id], groupName: groupName);
    } else {
      if (participants != null) {
        sessions[id]!.participants
          ..clear()
          ..addAll(participants);
      }
      if (groupName != null) {
        sessions[id]!.groupName = groupName;
      }
    }
    activeSession ??= id;
  }

  void switchSession(String id) {
    addSession(id);
    activeSession = id;
    windowOffset = sessionList.indexOf(id);
    sessions[id]!.unreadCount = 0;
    requestRedraw();
  }

  // Find existing session with the same participant set
  String? findSessionWithParticipants(List<String> participants) {
    var sortedParticipants = participants.toSet().toList()..sort();

    for (var entry in sessions.entries) {
      var sessionParticipants = entry.value.participants.toSet().toList()
        ..sort();
      if (sessionParticipants.length == sortedParticipants.length &&
          sessionParticipants.every((p) => sortedParticipants.contains(p))) {
        return entry.key;
      }
    }
    return null;
  }

  // Generate session key based on participants
  String generateSessionKey(List<String> participants) {
    var sortedParticipants = participants.toSet().toList()..sort();
    if (sortedParticipants.length == 2 &&
        sortedParticipants.contains(myAtSign)) {
      // Individual chat: use the other person's atSign as the key
      return sortedParticipants.firstWhere((p) => p != myAtSign);
    } else {
      // Group chat: use comma-separated sorted list
      return sortedParticipants.join(',');
    }
  }

  void requestRedraw() {
    redrawRequested = true;
  }

  void addMessage(String id, String message,
      {bool incoming = false, String? sender}) {
    addSession(id);
    final prefix = incoming
        ? (sender != null ? chalk.green('$sender: ') : chalk.yellow('me: '))
        : chalk.yellow('me: ');

    // Highlight "file sent" if it appears at the beginning of the message
    String processedMessage = message;
    if (message.startsWith('file sent\n')) {
      processedMessage = chalk.cyan.bold('file sent') +
          message.substring(9); // 9 = length of "file sent"
    }

    sessions[id]!.messages.add(prefix + processedMessage);
    if (incoming && activeSession != id) {
      sessions[id]!.unreadCount++;
    }
    if (activeSession == id) {
      requestRedraw();
    }
  }

  void nextWindow() {
    if (sessions.isEmpty) return;
    windowOffset = (windowOffset + 1) % sessions.length;
    activeSession = sessionList[windowOffset];
    if (sessions[activeSession!]!.unreadCount > 0) {
      sessions[activeSession!]!.unreadCount = 0;
      requestRedraw();
    }
  }

  void prevWindow() {
    if (sessions.isEmpty) return;
    windowOffset = (windowOffset - 1 + sessions.length) % sessions.length;
    activeSession = sessionList[windowOffset];
    if (sessions[activeSession!]!.unreadCount > 0) {
      sessions[activeSession!]!.unreadCount = 0;
      requestRedraw();
    }
  }

  void scrollUp() {
    if (activeSession == null) return;
    final session = sessions[activeSession!]!;
    if (session.scrollOffset < session.messages.length - 1) {
      session.scrollOffset++;
    }
  }

  void scrollDown() {
    if (activeSession == null) return;
    final session = sessions[activeSession!]!;
    if (session.scrollOffset > 0) {
      session.scrollOffset--;
    }
  }

  String stripAnsi(String input) {
    return input.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }

  // Word wrap helper for chat messages
  List<String> wrapText(String text, int maxWidth) {
    if (maxWidth <= 0) return [text];

    List<String> lines = [];

    // First split on existing newlines
    List<String> paragraphs = text.split('\n');

    for (String paragraph in paragraphs) {
      if (paragraph.isEmpty) {
        lines.add('');
        continue;
      }

      List<String> words = paragraph.split(' ');
      String currentLine = '';

      for (String word in words) {
        // Check if adding this word would exceed the width
        String testLine = currentLine.isEmpty ? word : '$currentLine $word';

        // Use stripAnsi to get actual visible length for width calculation
        if (stripAnsi(testLine).length <= maxWidth) {
          currentLine = testLine;
        } else {
          // If current line is not empty, save it and start new line
          if (currentLine.isNotEmpty) {
            lines.add(currentLine);
            currentLine = '';
          }

          // Handle case where single word is longer than maxWidth
          if (stripAnsi(word).length > maxWidth) {
            // Split the word into chunks that fit
            String remainingWord = word;
            while (stripAnsi(remainingWord).length > maxWidth) {
              // Find the best break point that preserves ANSI codes
              int visibleCount = 0;
              int breakPoint = 0;
              bool inAnsiSequence = false;

              for (int i = 0;
                  i < remainingWord.length && visibleCount < maxWidth;
                  i++) {
                if (remainingWord[i] == '\x1B') {
                  inAnsiSequence = true;
                } else if (inAnsiSequence && remainingWord[i] == 'm') {
                  inAnsiSequence = false;
                } else if (!inAnsiSequence) {
                  visibleCount++;
                }

                if (visibleCount <= maxWidth) {
                  breakPoint = i + 1;
                }
              }

              String chunk = remainingWord.substring(0, breakPoint);
              lines.add(chunk);
              remainingWord = remainingWord.substring(breakPoint);
            }

            // Add the remaining part of the word to current line
            currentLine = remainingWord;
          } else {
            currentLine = word;
          }
        }
      }

      // Add the last line of this paragraph if it's not empty
      if (currentLine.isNotEmpty) {
        lines.add(currentLine);
        currentLine = '';
      }
    }

    return lines.isEmpty ? [''] : lines;
  }

  // Fuzzy matching helper for session switching
  String? findBestMatch(String query) {
    if (query.isEmpty) return null;

    // Get candidates excluding the current active session
    var candidates = sessions.keys.where((id) => id != activeSession).toList();

    // First try exact match (excluding current session)
    if (candidates.contains(query)) return query;

    // Then try partial matches
    var matches = <String>[];

    // Look for sessions that contain the query (case insensitive)
    for (var sessionId in candidates) {
      if (sessionId.toLowerCase().contains(query.toLowerCase())) {
        matches.add(sessionId);
      }
    }

    // If we have matches, return the shortest one (most likely match)
    if (matches.isNotEmpty) {
      matches.sort((a, b) => a.length.compareTo(b.length));
      return matches.first;
    }

    return null;
  }

  void draw() {
    final termWidth = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final termHeight = stdout.hasTerminal ? stdout.terminalLines : 24;
    final sessionWidth = 20;
    final chatWidth = termWidth - sessionWidth - 2;
    final chatHeight = termHeight - 5;
    stdout.write('\x1b[2J\x1b[H');
    stdout
        .writeln(chalk.bold('atTalk TUI -  24{myAtSign}').padRight(termWidth));
    stdout.writeln('─' * termWidth);
    if (activeSession != null) {
      var session = sessions[activeSession!]!;
      var sortedParticipants = [
        myAtSign,
        ...session.participants.where((p) => p != myAtSign)
      ];
      var participants = sortedParticipants
          .map((p) => p == myAtSign ? chalk.yellow.bold(p) : chalk.cyan(p))
          .join(', ');
      stdout.writeln(chalk.cyan(' Participants: ') + participants);
      // Draw a line under participants, joining the session list and chat window
      stdout.write(chalk.yellow('├' + '─' * (sessionWidth - 1)));
      stdout.writeln(chalk.yellow('┬' + '─' * (chatWidth - 1) + '┤'));
    }
    List<String> chatLines = [];
    if (activeSession != null) {
      var session = sessions[activeSession!]!;
      int maxLines = chatHeight;

      // Process messages with word wrapping
      List<String> wrappedMessages = [];
      for (String message in session.messages) {
        List<String> wrapped =
            wrapText(message, chatWidth - 2); // -2 for padding
        wrappedMessages.addAll(wrapped);
      }

      int start = (wrappedMessages.length - maxLines - session.scrollOffset)
          .clamp(0, wrappedMessages.length);
      int end = (wrappedMessages.length - session.scrollOffset)
          .clamp(0, wrappedMessages.length);
      for (int i = start; i < end; i++) {
        chatLines.add(wrappedMessages[i]);
      }
      while (chatLines.length < chatHeight) {
        chatLines.insert(0, '');
      }
    } else {
      chatLines = List.filled(chatHeight, '');
    }
    for (int i = 0; i < chatHeight; i++) {
      String sessionLine = '';
      if (i < sessionList.length) {
        var s = sessionList[i];
        var marker = (i == windowOffset) ? chalk.yellow('>') : ' ';
        int unread = sessions[s]!.unreadCount;
        String unreadStr = '';
        if (unread > 0) {
          if (unread > 99) {
            unreadStr = chalk.red.bold('** ');
          } else {
            unreadStr = chalk.red.bold(unread.toString().padLeft(2, '0') + ' ');
          }
        } else {
          unreadStr = '   ';
        }
        sessionLine = unreadStr +
            marker +
            ' ' +
            sessions[s]!
                .getDisplayName(myAtSign)
                .padRight(sessionWidth - 6 - marker.length);
      } else {
        sessionLine = ' '.padRight(sessionWidth);
      }
      int visibleLen = stripAnsi(sessionLine).length;
      if (visibleLen < sessionWidth) {
        stdout.write(sessionLine + ' ' * (sessionWidth - visibleLen));
      } else if (visibleLen > sessionWidth) {
        int count = 0;
        String out = '';
        for (int j = 0; j < sessionLine.length && count < sessionWidth; j++) {
          if (sessionLine[j] == '\x1B') {
            int m = sessionLine.indexOf('m', j);
            if (m != -1) {
              out += sessionLine.substring(j, m + 1);
              j = m;
            }
          } else {
            out += sessionLine[j];
            count++;
          }
        }
        stdout.write(out);
      } else {
        stdout.write(sessionLine);
      }
      stdout.write(chalk.yellow('│'));
      stdout.writeln(chatLines[i].padRight(chatWidth));
    }
    stdout.writeln('─' * termWidth);
    updateInputDisplay();
  }

  void showHelpPanel() {
    final termWidth = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final termHeight = stdout.hasTerminal ? stdout.terminalLines : 24;
    final helpLines = [
      'atTalk TUI Help',
      '',
      'Text Commands:',
      '  /switch @other   Switch to chat with @other',
      '  /new @other      Start new chat with @other',
      '  /add @other      Add participant to group',
      '  /remove @other   Remove participant from group',
      '  /rename name     Rename current group',
      '  /delete          Delete current session',
      '  /list            Show group info panel',
      '  /exit            Quit',
      '',
      'Press Escape to close this help panel.'
    ];
    int panelWidth = 50;
    int panelHeight = helpLines.length + 2;
    int left = ((termWidth - panelWidth) ~/ 2).clamp(0, termWidth - 1);
    int top = ((termHeight - panelHeight) ~/ 2).clamp(0, termHeight - 1);

    // Save cursor position
    stdout.write('\x1b[s');

    // Draw overlay panel
    for (int i = 0; i < helpLines.length + 2; i++) {
      stdout.write('\x1b[${top + i + 1};${left + 1}H');
      if (i == 0) {
        stdout.write(chalk.yellow('┌' + '─' * (panelWidth - 2) + '┐'));
      } else if (i == helpLines.length + 1) {
        stdout.write(chalk.yellow('└' + '─' * (panelWidth - 2) + '┘'));
      } else {
        String line = helpLines[i - 1].padRight(panelWidth - 2);
        stdout.write(chalk.yellow('│') + chalk.bold(line) + chalk.yellow('│'));
      }
    }

    // Wait for Escape key
    stdin.echoMode = false;
    stdin.lineMode = false;

    while (true) {
      int key = stdin.readByteSync();
      if (key == 27) {
        // Escape key - always close help panel
        break;
      }
    }

    // Restore screen
    draw();
  }

  Future<void> showParticipantsPanel() async {
    if (activeSession == null) return;
    final session = sessions[activeSession!]!;
    final termWidth = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final termHeight = stdout.hasTerminal ? stdout.terminalLines : 24;
    final panelWidth = 50; // Increased width for better layout
    final maxPanelHeight = termHeight - 8;

    int scroll = 0;
    String inputBuffer = '';
    bool isInputMode = false;
    String inputPrompt = '';
    int inputAction = 0; // 1: rename, 2: add, 3: remove

    stdin.echoMode = false;
    stdin.lineMode = false;

    while (true) {
      final participants = [
        myAtSign,
        ...session.participants.where((p) => p != myAtSign)
      ];

      // Calculate visible count for participants
      int visibleCount = (participants.length < maxPanelHeight - 8)
          ? participants.length
          : (maxPanelHeight - 8);

      // Draw the enhanced panel
      _drawEnhancedParticipantsPanel(
          participants,
          scroll,
          visibleCount,
          panelWidth,
          termWidth,
          termHeight,
          isInputMode,
          inputBuffer,
          inputPrompt,
          session);

      // Wait for input
      int key = stdin.readByteSync();

      if (isInputMode) {
        // Handle input mode
        if (key == 27) {
          // Escape - cancel input
          isInputMode = false;
          inputBuffer = '';
          inputAction = 0;
        } else if (key == 13 || key == 10) {
          // Enter - submit input
          if (inputBuffer.trim().isNotEmpty) {
            if (inputAction == 1) {
              // Rename
              session.groupName = inputBuffer.trim();
              var displayName = session.groupName ?? 'Unnamed Group';
              addMessage(activeSession!, '[Group renamed to "$displayName"]',
                  incoming: true);
              if (onGroupRename != null) {
                onGroupRename!(activeSession!, inputBuffer.trim());
              }
            } else if (inputAction == 2) {
              // Add participant
              var newParticipant = inputBuffer.trim();
              if (!session.participants.contains(newParticipant) &&
                  newParticipant != myAtSign) {
                // Check if this will create a group (3+ participants)
                if (session.participants.length == 2) {
                  // Converting from individual chat to group - use same logic as command
                  var newParticipants = session.participants.toList()
                    ..add(newParticipant);

                  // Set up for group name prompting and session transition
                  _waitingForGroupName = true;
                  _pendingParticipants = newParticipants;
                  _pendingSessionKey = activeSession!;

                  addMessage(
                      activeSession!, '[Added $newParticipant to the chat]',
                      incoming: true);
                  addMessage(activeSession!,
                      '[Enter a name for this group (or press Enter for no name):]',
                      incoming: true);
                  requestRedraw();
                  break; // Exit panel to handle group naming
                } else {
                  // Already a group - just add participant
                  session.participants.add(newParticipant);
                  addMessage(
                      activeSession!, '[Added $newParticipant to the chat]',
                      incoming: true);
                }
              }
            } else if (inputAction == 3) {
              // Remove participant
              var participantToRemove = inputBuffer.trim();
              if (session.participants.contains(participantToRemove) &&
                  participantToRemove != myAtSign) {
                // Simply remove from the current session, preserving group name and messages
                session.participants.remove(participantToRemove);
                addMessage(activeSession!,
                    '[Removed $participantToRemove from the chat]',
                    incoming: true);
              }
            }
          }
          isInputMode = false;
          inputBuffer = '';
          inputAction = 0;
          requestRedraw();
        } else if (key == 127 || key == 8) {
          // Backspace
          if (inputBuffer.isNotEmpty) {
            inputBuffer = inputBuffer.substring(0, inputBuffer.length - 1);
          }
        } else if (key >= 32 && key <= 126) {
          // Printable characters
          inputBuffer += String.fromCharCode(key);
        }
      } else {
        // Handle navigation mode
        if (key == 27) {
          // Escape key
          break;
        } else if (key == 106 && scroll < participants.length - visibleCount) {
          // 'j' - scroll down
          scroll++;
        } else if (key == 107 && scroll > 0) {
          // 'k' - scroll up
          scroll--;
        } else if (key == 114) {
          // 'r' - rename group
          if (session.participants.length >= 3) {
            // Only for groups
            inputAction = 1;
            isInputMode = true;
            inputBuffer = session.groupName ?? '';
            inputPrompt = 'Enter new group name:';
          }
        } else if (key == 97) {
          // 'a' - add participant
          inputAction = 2;
          isInputMode = true;
          inputBuffer = '';
          inputPrompt = 'Enter atSign to add:';
        } else if (key == 100) {
          // 'd' - remove participant (delete)
          if (session.participants.length > 2) {
            // Don't allow removing from 1-on-1 chats
            inputAction = 3;
            isInputMode = true;
            inputBuffer = '';
            inputPrompt = 'Enter atSign to remove:';
          }
        }
      }
    }

    draw();
  }

  void _drawEnhancedParticipantsPanel(
      List<String> participants,
      int scroll,
      int visibleCount,
      int panelWidth,
      int termWidth,
      int termHeight,
      bool isInputMode,
      String inputBuffer,
      String inputPrompt,
      ChatSession session) {
    int panelHeight = visibleCount + 8; // Increased for buttons
    int left = ((termWidth - panelWidth) ~/ 2).clamp(0, termWidth - 1);
    int top = ((termHeight - panelHeight) ~/ 2).clamp(0, termHeight - 1);

    // Draw overlay panel
    for (int i = 0; i < panelHeight; i++) {
      stdout.write('\x1b[${top + i + 1};${left + 1}H');
      if (i == 0) {
        stdout.write(chalk.yellow('┌' + '─' * (panelWidth - 2) + '┐'));
      } else if (i == 2 || i == panelHeight - 5) {
        stdout.write(chalk.yellow('├' + '─' * (panelWidth - 2) + '┤'));
      } else if (i == panelHeight - 1) {
        stdout.write(chalk.yellow('└' + '─' * (panelWidth - 2) + '┘'));
      } else if (i == 1) {
        // Title with group name and scroll indicators
        String title = session.groupName != null
            ? chalk.bold(' Group: ${session.groupName}')
            : chalk.bold(' Participants (${participants.length})');
        String scrollInfo = '';
        if (participants.length > visibleCount) {
          String upIndicator = scroll > 0 ? '↑' : ' ';
          String downIndicator =
              scroll < participants.length - visibleCount ? '↓' : ' ';
          scrollInfo = ' $upIndicator$downIndicator ';
        }
        int titleVisibleLen = stripAnsi(session.groupName != null
                    ? ' Group: ${session.groupName}'
                    : ' Participants (${participants.length})')
                .length +
            scrollInfo.length;
        String titleLine =
            title + scrollInfo + ' ' * (panelWidth - 2 - titleVisibleLen);
        stdout.write(chalk.yellow('│') + titleLine + chalk.yellow('│'));
      } else if (i >= 3 && i < 3 + visibleCount) {
        // Participant list
        int participantIndex = i - 3 + scroll;
        if (participantIndex < participants.length) {
          String p = participants[participantIndex];
          String displayName =
              (p == myAtSign ? chalk.yellow.bold(p) : chalk.cyan(p));
          int visibleLen = stripAnsi(displayName).length;
          String line = displayName + ' ' * (panelWidth - 2 - visibleLen);
          stdout.write(chalk.yellow('│') + line + chalk.yellow('│'));
        } else {
          stdout.write(chalk.yellow('│' + ' ' * (panelWidth - 2) + '│'));
        }
      } else if (i == panelHeight - 4) {
        // Rename button (only for groups)
        String renameText = session.participants.length >= 3
            ? chalk.cyan(' [r] Rename Group')
            : chalk.gray(' [r] Rename Group (groups only)');
        String line =
            renameText + ' ' * (panelWidth - 2 - stripAnsi(renameText).length);
        stdout.write(chalk.yellow('│') + line + chalk.yellow('│'));
      } else if (i == panelHeight - 3) {
        // Add participant button
        String addText = chalk.green(' [a] Add Participant');
        String line =
            addText + ' ' * (panelWidth - 2 - stripAnsi(addText).length);
        stdout.write(chalk.yellow('│') + line + chalk.yellow('│'));
      } else if (i == panelHeight - 2) {
        // Remove participant button (only if more than 2 participants)
        String removeText = session.participants.length > 2
            ? chalk.red(' [d] Remove Participant')
            : chalk.gray(' [d] Remove Participant (groups only)');
        String line =
            removeText + ' ' * (panelWidth - 2 - stripAnsi(removeText).length);
        stdout.write(chalk.yellow('│') + line + chalk.yellow('│'));
      } else {
        stdout.write(chalk.yellow('│' + ' ' * (panelWidth - 2) + '│'));
      }
    }

    // Show input prompt or instructions below panel
    stdout.write('\x1b[${top + panelHeight + 1};${left + 1}H');
    if (isInputMode) {
      String promptLine = chalk.bold(inputPrompt + ' ') + inputBuffer;
      stdout.write(promptLine.padRight(panelWidth));
      stdout.write('\x1b[${top + panelHeight + 2};${left + 1}H');
      stdout.write(chalk
          .dim('[Enter] to confirm, [Esc] to cancel')
          .padRight(panelWidth));
    } else {
      if (participants.length > visibleCount) {
        stdout.write(chalk
            .bold('Use j/k to scroll, [Esc] to close.')
            .padRight(panelWidth));
      } else {
        stdout.write(chalk
            .bold('Use action keys or [Esc] to close.')
            .padRight(panelWidth));
      }
    }
  }

  void deleteSession(String id) {
    if (sessions.containsKey(id)) {
      sessions.remove(id);
      if (activeSession == id) {
        activeSession = sessions.isNotEmpty ? sessionList.first : null;
        windowOffset = 0;
      }
      requestRedraw();
    }
  }

  void updateInputDisplay() {
    final termWidth = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final termHeight = stdout.hasTerminal ? stdout.terminalLines : 24;
    final maxInputWidth = termWidth - 3; // Account for "> " prefix

    // Adjust scroll offset to keep cursor visible
    if (inputCursorPos < inputScrollOffset) {
      inputScrollOffset = inputCursorPos;
    } else if (inputCursorPos >= inputScrollOffset + maxInputWidth) {
      inputScrollOffset = inputCursorPos - maxInputWidth + 1;
    }

    // Extract visible portion of input
    String visibleInput;
    int visibleCursorPos = inputCursorPos - inputScrollOffset;

    if (inputBuffer.length <= maxInputWidth) {
      // Input fits entirely, show it all
      visibleInput = inputBuffer;
      visibleCursorPos = inputCursorPos;
      inputScrollOffset = 0; // Reset scroll when input is short enough
    } else {
      // Input is too long, show visible portion
      int startPos = inputScrollOffset;
      int endPos =
          (inputScrollOffset + maxInputWidth).clamp(0, inputBuffer.length);
      visibleInput = inputBuffer.substring(startPos, endPos);

      // Add scroll indicators without affecting cursor position
      if (inputScrollOffset > 0 && visibleInput.isNotEmpty) {
        visibleInput = '<' + visibleInput.substring(1);
        if (visibleCursorPos == 0)
          visibleCursorPos = 1; // Adjust cursor if at start
      }
      if (endPos < inputBuffer.length && visibleInput.isNotEmpty) {
        visibleInput = visibleInput.substring(0, visibleInput.length - 1) + '>';
        if (visibleCursorPos >= visibleInput.length)
          visibleCursorPos = visibleInput.length - 1;
      }
    }

    // Clear the input line and redraw
    stdout.write('\x1b[${termHeight};1H\x1b[K');

    if (inputBuffer.isEmpty && showHelpHint) {
      // Show greyed-out help hint when input is empty
      stdout.write('> ');
      stdout
          .write('\x1b[90m /? for help\x1b[0m'); // 90m = dark grey, 0m = reset
      stdout.write('\x1b[${termHeight};3H'); // Position cursor after "> "
    } else {
      stdout.write('> $visibleInput');
      stdout.write('\x1b[${termHeight};${visibleCursorPos + 3}H');
    }
  }

  Future<void> run() async {
    stdin.echoMode = false;
    stdin.lineMode = false;
    draw();

    // Listen for terminal resize events (SIGWINCH)
    ProcessSignal.sigwinch.watch().listen((_) {
      requestRedraw();
    });

    // Timer for redraw requests
    Timer.periodic(Duration(milliseconds: 100), (_) {
      if (redrawRequested) {
        draw();
        redrawRequested = false;
      }
    });

    // Reset input state
    inputBuffer = '';
    inputCursorPos = 0;
    List<int> escapeSequence = [];
    bool inEscapeSequence = false;

    await for (final charCodes in stdin) {
      for (int charCode in charCodes) {
        // Handle escape sequences (arrow keys)
        if (charCode == 27) {
          // ESC
          escapeSequence = [27];
          inEscapeSequence = true;
          continue;
        }

        if (inEscapeSequence) {
          escapeSequence.add(charCode);

          // Check for complete arrow key sequences: ESC [ A/B/C/D
          if (escapeSequence.length == 3 && escapeSequence[1] == 91) {
            // ESC [
            switch (escapeSequence[2]) {
              case 65: // Up arrow (ESC [ A)
                scrollUp();
                requestRedraw();
                break;
              case 66: // Down arrow (ESC [ B)
                scrollDown();
                requestRedraw();
                break;
              case 67: // Right arrow (ESC [ C)
                if (inputBuffer.isNotEmpty) {
                  // Input has content - move cursor in input field
                  if (inputCursorPos < inputBuffer.length) {
                    inputCursorPos++;
                    updateInputDisplay();
                  }
                } else {
                  // Input is empty - navigate to next session
                  nextWindow();
                  requestRedraw();
                }
                break;
              case 68: // Left arrow (ESC [ D)
                if (inputBuffer.isNotEmpty) {
                  // Input has content - move cursor in input field
                  if (inputCursorPos > 0) {
                    inputCursorPos--;
                    updateInputDisplay();
                  }
                } else {
                  // Input is empty - navigate to previous session
                  prevWindow();
                  requestRedraw();
                }
                break;
            }
            inEscapeSequence = false;
            escapeSequence.clear();
            continue;
          }
          // Reset if we get an unexpected sequence
          if (escapeSequence.length > 5) {
            inEscapeSequence = false;
            escapeSequence.clear();
          }
          continue;
        }

        // Handle regular characters
        if (charCode == 12) {
          // Ctrl+L - refresh screen immediately
          draw();
          continue;
        } else if (charCode == 13 || charCode == 10) {
          // Enter
          String input = inputBuffer.trim();
          inputBuffer = '';
          inputCursorPos = 0;
          inputScrollOffset = 0;

          // Clear the input line
          final termHeight = stdout.hasTerminal ? stdout.terminalLines : 24;
          stdout.write('\x1b[${termHeight};1H\x1b[K> ');

          // Check if we're waiting for a group name
          if (_waitingForGroupName &&
              _pendingParticipants != null &&
              _pendingSessionKey != null) {
            _waitingForGroupName = false;
            var groupName = input.isNotEmpty ? input : null;
            var oldSessionKey = _pendingSessionKey!;
            var oldSession = sessions[oldSessionKey]!;

            // Generate new session key for the group
            var newSessionKey = generateSessionKey(_pendingParticipants!);

            // If the session key changes (individual to group), migrate the session
            if (newSessionKey != oldSessionKey) {
              // Create new session with group participants and name
              addSession(newSessionKey, _pendingParticipants!, groupName);

              // Transfer all messages from old session to new session
              sessions[newSessionKey]!.messages.addAll(oldSession.messages);

              // Remove old session
              sessions.remove(oldSessionKey);

              // Switch to new session
              activeSession = newSessionKey;
              windowOffset = sessionList.indexOf(newSessionKey);
            } else {
              // Same session key, just update participants and group name
              oldSession.participants.clear();
              oldSession.participants.addAll(_pendingParticipants!);
              oldSession.groupName = groupName;
            }

            // Clear the prompt message (it was the last one added)
            if (sessions[activeSession!]!.messages.isNotEmpty &&
                sessions[activeSession!]!
                    .messages
                    .last
                    .contains('[Enter a name for this group')) {
              sessions[activeSession!]!.messages.removeLast();
            }

            var displayName =
                groupName?.isNotEmpty == true ? groupName! : 'Unnamed Group';
            addMessage(activeSession!, '[Group "$displayName" created]',
                incoming: true);

            // Clear pending state
            _pendingParticipants = null;
            _pendingSessionKey = null;
            requestRedraw();
            continue;
          }

          if (input == '/?') {
            showHelpPanel();
            continue;
          } else if (input.startsWith('/switch ')) {
            var query = input.substring(8).trim();
            var bestMatch = findBestMatch(query);
            if (bestMatch != null) {
              switchSession(bestMatch);
            } else {
              // Create a new session if no match found
              switchSession(query);
            }
          } else if (input.startsWith('/new ')) {
            var rest = input.substring(5).trim();
            var ids = rest
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (ids.length == 1) {
              // Individual chat: include both sender and receiver in participants
              var individualParticipants = [myAtSign, ids[0]].toSet().toList()
                ..sort();
              addSession(ids[0], individualParticipants);
              switchSession(ids[0]);
            } else if (ids.length > 1) {
              // Group chat: include myself in the participants list for consistency
              ids.add(myAtSign);
              var allParticipants = ids.toSet().toList()..sort();
              var groupKey = allParticipants.join(',');

              // Create and switch to the new group session immediately
              addSession(groupKey, allParticipants);
              switchSession(groupKey);

              // Clear the chat window by starting fresh
              sessions[groupKey]!.messages.clear();

              // Set up for group name prompting
              _waitingForGroupName = true;
              _pendingParticipants = allParticipants;
              _pendingSessionKey = groupKey;

              // Add the prompt message to the clean session
              addMessage(groupKey,
                  '[Enter a name for this group (or press Enter for no name):]',
                  incoming: true);
              requestRedraw();
            }
          } else if (input == '/delete') {
            if (activeSession != null) deleteSession(activeSession!);
          } else if (input.startsWith('/rename ')) {
            var newName = input.substring(8).trim();
            if (activeSession != null) {
              var session = sessions[activeSession!]!;
              session.groupName = newName.isNotEmpty ? newName : null;

              var displayName = session.groupName ?? 'Unnamed Group';
              addMessage(activeSession!, '[Group renamed to "$displayName"]',
                  incoming: true);

              // Notify other participants of the rename
              if (onGroupRename != null) {
                onGroupRename!(activeSession!, newName);
              }

              requestRedraw();
            }
          } else if (input.startsWith('/add ')) {
            var newParticipant = input.substring(5).trim();
            if (activeSession != null && newParticipant.isNotEmpty) {
              var session = sessions[activeSession!]!;
              if (!session.participants.contains(newParticipant)) {
                // Check if this will create a group (3+ participants)
                if (session.participants.length == 2) {
                  // Converting from individual chat to group
                  var newParticipants = session.participants.toList()
                    ..add(newParticipant);

                  // Set up for group name prompting and session transition
                  _waitingForGroupName = true;
                  _pendingParticipants = newParticipants;
                  _pendingSessionKey =
                      activeSession!; // Store current session for migration

                  addMessage(
                      activeSession!, '[Added $newParticipant to the chat]',
                      incoming: true);
                  addMessage(activeSession!,
                      '[Enter a name for this group (or press Enter for no name):]',
                      incoming: true);
                  requestRedraw();
                } else {
                  // Already a group - just add participant
                  session.participants.add(newParticipant);
                  addMessage(
                      activeSession!, '[Added $newParticipant to the chat]',
                      incoming: true);
                }
              } else {
                addMessage(activeSession!,
                    '[Participant $newParticipant is already in this chat]',
                    incoming: true);
              }
            }
          } else if (input.startsWith('/remove ')) {
            var participantToRemove = input.substring(8).trim();
            if (activeSession != null && participantToRemove.isNotEmpty) {
              var session = sessions[activeSession!]!;
              if (session.participants.contains(participantToRemove)) {
                // Don't allow removing yourself from the chat
                if (participantToRemove != myAtSign) {
                  // Simply remove from the current session, preserving group name and messages
                  session.participants.remove(participantToRemove);
                  addMessage(activeSession!,
                      '[Removed $participantToRemove from the chat]',
                      incoming: true);
                } else {
                  // Show error message - can't remove yourself
                  addMessage(
                      activeSession!, '[Cannot remove yourself from chat]',
                      incoming: true);
                }
              } else {
                // Show error message - participant not found
                addMessage(activeSession!,
                    '[Participant $participantToRemove not found in chat]',
                    incoming: true);
              }
            }
          } else if (input == '/list') {
            await showParticipantsPanel();
            continue;
          } else if (input == '/exit') {
            break;
          } else if (activeSession != null && input.isNotEmpty) {
            // CRITICAL: Preserve message sending functionality
            addMessage(activeSession!, input);
            if (onSend != null) {
              onSend!(activeSession!, input);
            }
          }
          draw();
        } else if (charCode == 127 || charCode == 8) {
          // Backspace/Delete
          if (inputBuffer.isNotEmpty && inputCursorPos > 0) {
            inputBuffer = inputBuffer.substring(0, inputCursorPos - 1) +
                inputBuffer.substring(inputCursorPos);
            inputCursorPos--;
            updateInputDisplay();
          }
        } else if (charCode >= 32 && charCode <= 126) {
          // Printable characters
          String char = String.fromCharCode(charCode);

          // Hide help hint when user starts typing
          if (showHelpHint) {
            showHelpHint = false;
          }

          inputBuffer = inputBuffer.substring(0, inputCursorPos) +
              char +
              inputBuffer.substring(inputCursorPos);
          inputCursorPos++;
          updateInputDisplay();
        }
      }
    }

    stdin.echoMode = true;
    stdin.lineMode = true;
  }
}
