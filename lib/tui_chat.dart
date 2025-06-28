import 'package:at_talk/at_talk.dart';
import 'package:chalkdart/chalk.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';

// This is a placeholder for a TUI implementation using only pure Dart.
// It will allow multiple chat sessions with different atSigns in separate windows (panes).
// This is a minimal TUI engine using ANSI escape codes and stdin.
// For a real-world app, you would want to refactor and modularize this further.

class ChatSession {
  final String id; // could be single atSign or group id
  final List<String> participants;
  final List<String> messages = [];
  int scrollOffset = 0;
  int unreadCount = 0;
  ChatSession(this.id, this.participants);
}

class TuiChatApp {
  final String myAtSign;
  final Map<String, ChatSession> sessions = {};
  String? activeSession;
  void Function(String atSign, String message)? onSend;

  // Add a windowed mode for multiple chat panes (tmux-like)
  int windowOffset = 0;
  int windowSize = 1;
  List<String> get sessionList => sessions.keys.toList();

  String inputBuffer = '';
  bool redrawRequested = false;

  TuiChatApp(this.myAtSign);

  void addSession(String id, [List<String>? participants]) {
    if (!sessions.containsKey(id)) {
      sessions[id] = ChatSession(id, participants ?? [id]);
    } else if (participants != null) {
      // Always update the participant list to the latest (for group chats)
      sessions[id]!.participants
        ..clear()
        ..addAll(participants);
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

  void requestRedraw() {
    redrawRequested = true;
  }

  void addMessage(String id, String message, {bool incoming = false}) {
    addSession(id);
    final prefix = incoming ? chalk.green('$id: ') : chalk.blue('me: ');
    sessions[id]!.messages.add(prefix + message);
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
    // Mark all as read when switching
    if (sessions[activeSession!]!.unreadCount > 0) {
      sessions[activeSession!]!.unreadCount = 0;
      requestRedraw();
    }
  }

  void prevWindow() {
    if (sessions.isEmpty) return;
    windowOffset = (windowOffset - 1 + sessions.length) % sessions.length;
    activeSession = sessionList[windowOffset];
    // Mark all as read when switching
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

  // Utility to strip ANSI color codes for width calculation
  String stripAnsi(String input) {
    return input.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }

  void draw() {
    final termWidth = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final termHeight = stdout.hasTerminal ? stdout.terminalLines : 24;
    final sessionWidth = 20;
    final chatWidth = termWidth - sessionWidth - 2;
    final chatHeight = termHeight - 5; // header + input + borders
    stdout.write('\x1b[2J\x1b[H'); // Clear screen
    // Header
    stdout.writeln(chalk.bold('atTalk TUI - ${myAtSign}').padRight(termWidth));
    stdout.writeln('─' * termWidth);
    // Show group participants in chat pane header
    if (activeSession != null) {
      var session = sessions[activeSession!]!;
      // List my atSign first, highlight it, then others
      var sortedParticipants = [
        myAtSign,
        ...session.participants.where((p) => p != myAtSign)
      ];
      var participants = sortedParticipants
          .map((p) => p == myAtSign ? chalk.yellow.bold(p) : chalk.cyan(p))
          .join(', ');
      stdout.writeln(chalk.cyan('Participants: ') + participants);
      // Draw a line under participants, joining the session list and chat window
      stdout.write(chalk.yellow('├' + '─' * (sessionWidth - 1)));
      stdout.writeln(chalk.yellow('┼' + '─' * (chatWidth - 1)));
    }
    // Prepare chat lines for active session
    List<String> chatLines = [];
    if (activeSession != null) {
      var session = sessions[activeSession!]!;
      int maxLines = chatHeight;
      int start = (session.messages.length - maxLines - session.scrollOffset)
          .clamp(0, session.messages.length);
      int end = (session.messages.length - session.scrollOffset)
          .clamp(0, session.messages.length);
      for (int i = start; i < end; i++) {
        chatLines.add(session.messages[i]);
      }
      while (chatLines.length < chatHeight) {
        chatLines.insert(0, '');
      }
    } else {
      chatLines = List.filled(chatHeight, '');
    }
    // Session list (left) and chat pane (right)
    for (int i = 0; i < chatHeight; i++) {
      String sessionLine = '';
      if (i < sessionList.length) {
        var s = sessionList[i];
        var marker = (i == windowOffset) ? chalk.yellow('>') : ' ';
        // Format unread count: left, no brackets, two digits, ** for >99
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
            s.padRight(sessionWidth - 6 - marker.length);
      } else {
        sessionLine = ' '.padRight(sessionWidth);
      }
      // Pad/truncate sessionLine so | is always at the same visible column
      int visibleLen = stripAnsi(sessionLine).length;
      if (visibleLen < sessionWidth) {
        stdout.write(sessionLine + ' ' * (sessionWidth - visibleLen));
      } else if (visibleLen > sessionWidth) {
        // Truncate visible part, but keep color codes
        int count = 0;
        String out = '';
        for (int j = 0; j < sessionLine.length && count < sessionWidth; j++) {
          if (sessionLine[j] == '\x1B') {
            // Start of ANSI code
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
      // Print chat line for this row
      stdout.writeln(chatLines[i].padRight(chatWidth));
    }
    stdout.writeln('─' * termWidth);
    // Draw input at the last line
    int inputLine = termHeight;
    stdout.write('\x1b[${inputLine};1H');
    stdout.write('> ' + inputBuffer);
    // Move cursor to end of input
    stdout.write('\x1b[${inputBuffer.length + 3}G');
  }

  void showHelpPanel() {
    final termWidth = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final termHeight = stdout.hasTerminal ? stdout.terminalLines : 24;
    final helpLines = [
      'atTalk TUI Help',
      '',
      'Shortcuts:',
      '  /switch @other   Switch to chat with @other',
      '  /new @other      Start new chat with @other',
      '  /next            Next chat window',
      '  /prev            Previous chat window',
      '  /up              Scroll up in chat',
      '  /down            Scroll down in chat',
      '  /refresh         Redraw the screen',
      '  /exit            Quit',
      '',
      'Press Enter to close this help panel.'
    ];
    int panelWidth = 48;
    int panelHeight = helpLines.length + 2;
    int left = ((termWidth - panelWidth) ~/ 2).clamp(0, termWidth - 1);
    int top = ((termHeight - panelHeight) ~/ 2).clamp(0, termHeight - 1);
    // Draw panel border
    stdout.write('\x1b[2J\x1b[H');
    for (int i = 0; i < top; i++) stdout.writeln();
    stdout.write(' ' * left);
    stdout.writeln(chalk.yellow('┌' + '─' * (panelWidth - 2) + '┐'));
    for (int i = 0; i < helpLines.length; i++) {
      stdout.write(' ' * left);
      String line = helpLines[i].padRight(panelWidth - 2);
      stdout.writeln(chalk.yellow('│') + chalk.bold(line) + chalk.yellow('│'));
    }
    stdout.write(' ' * left);
    stdout.writeln(chalk.yellow('└' + '─' * (panelWidth - 2) + '┘'));
    // Wait for Enter
    stdin.readLineSync();
    draw();
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

  Future<void> run() async {
    stdin.echoMode = true;
    stdin.lineMode = true;
    draw();
    Timer.periodic(Duration(milliseconds: 100), (_) {
      if (redrawRequested) {
        draw();
        redrawRequested = false;
      }
    });
    var lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      String input = line.trim();
      inputBuffer = '';
      if (input == '/refresh') {
        draw();
        continue;
      } else if (input == '/?') {
        showHelpPanel();
        continue;
      } else if (input.startsWith('/switch ')) {
        var id = input.substring(8).trim();
        switchSession(id);
      } else if (input.startsWith('/new ')) {
        var rest = input.substring(5).trim();
        var ids = rest
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (ids.length == 1) {
          addSession(ids[0], ids);
          switchSession(ids[0]);
        } else if (ids.length > 1) {
          var groupId = ids.toSet().toList()..sort();
          var groupKey = groupId.join(',');
          addSession(groupKey, groupId);
          switchSession(groupKey);
        }
      } else if (input == '/next') {
        nextWindow();
      } else if (input == '/prev') {
        prevWindow();
      } else if (input == '/up') {
        scrollUp();
      } else if (input == '/down') {
        scrollDown();
      } else if (input == '/delete') {
        if (activeSession != null) deleteSession(activeSession!);
      } else if (input == '/exit') {
        break;
      } else if (activeSession != null && input.isNotEmpty) {
        addMessage(activeSession!, input);
        if (onSend != null) {
          onSend!(activeSession!, input);
        }
      }
      draw();
    }
    stdin.echoMode = true;
    stdin.lineMode = true;
  }
}

// To use this, instantiate TuiChatApp in your main and call run().
// You will need to integrate message sending/receiving with your atTalk logic.
