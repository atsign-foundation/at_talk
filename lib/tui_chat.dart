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
  final String atSign;
  final List<String> messages = [];
  int scrollOffset = 0; // For scrolling
  int unreadCount = 0; // Track unread messages
  ChatSession(this.atSign);
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

  void addSession(String atSign) {
    sessions.putIfAbsent(atSign, () => ChatSession(atSign));
    activeSession ??= atSign;
  }

  void switchSession(String atSign) {
    addSession(atSign); // Always ensure the session exists
    activeSession = atSign;
    windowOffset = sessionList.indexOf(atSign);
    // Mark all as read
    sessions[atSign]!.unreadCount = 0;
    requestRedraw();
  }

  void requestRedraw() {
    redrawRequested = true;
  }

  void addMessage(String atSign, String message, {bool incoming = false}) {
    addSession(atSign);
    final prefix = incoming ? chalk.green('$atSign: ') : chalk.blue('me: ');
    sessions[atSign]!.messages.add(prefix + message);
    if (incoming && activeSession != atSign) {
      sessions[atSign]!.unreadCount++;
    }
    if (activeSession == atSign) {
      requestRedraw();
    }
  }

  void nextWindow() {
    if (sessions.isEmpty) return;
    windowOffset = (windowOffset + 1) % sessions.length;
    activeSession = sessionList[windowOffset];
  }

  void prevWindow() {
    if (sessions.isEmpty) return;
    windowOffset = (windowOffset - 1 + sessions.length) % sessions.length;
    activeSession = sessionList[windowOffset];
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

  void draw() {
    final termWidth = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final termHeight = stdout.hasTerminal ? stdout.terminalLines : 24;
    final sessionWidth = 20;
    final chatWidth = termWidth - sessionWidth - 2;
    final chatHeight = termHeight - 5; // header + input + borders
    stdout.write('\x1b[2J\x1b[H'); // Clear screen
    // Header
    stdout.writeln(chalk.bold('atTalk TUI - @${myAtSign}').padRight(termWidth));
    stdout.writeln('─' * termWidth);
    // Prepare chat lines for active session
    List<String> chatLines = [];
    if (activeSession != null) {
      var session = sessions[activeSession!]!;
      int maxLines = chatHeight;
      int start = (session.messages.length - maxLines - session.scrollOffset).clamp(0, session.messages.length);
      int end = (session.messages.length - session.scrollOffset).clamp(0, session.messages.length);
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
        var unread = sessions[s]!.unreadCount > 0 ? chalk.red('(${sessions[s]!.unreadCount})') : '';
        sessionLine = marker + ' ' + s.padRight(sessionWidth - 6 - marker.length) + unread.toString().padRight(5 - marker.length);
      } else {
        sessionLine = ' '.padRight(sessionWidth);
      }
      stdout.write(sessionLine);
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

  Future<void> run() async {
    stdin.echoMode = true;
    stdin.lineMode = true;
    draw();
    // Listen for incoming messages and redraw
    Timer.periodic(Duration(milliseconds: 100), (_) {
      if (redrawRequested) {
        draw();
        redrawRequested = false;
      }
    });
    // Read lines from stdin
    var lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      String input = line.trim();
      inputBuffer = '';
      if (input.startsWith('/switch ')) {
        var atSign = input.substring(8).trim();
        switchSession(atSign);
      } else if (input.startsWith('/new ')) {
        var atSign = input.substring(5).trim();
        addSession(atSign);
        switchSession(atSign);
      } else if (input == '/next') {
        nextWindow();
      } else if (input == '/prev') {
        prevWindow();
      } else if (input == '/up') {
        scrollUp();
      } else if (input == '/down') {
        scrollDown();
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
