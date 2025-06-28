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

  TuiChatApp(this.myAtSign);

  void addSession(String atSign) {
    sessions.putIfAbsent(atSign, () => ChatSession(atSign));
    activeSession ??= atSign;
  }

  void switchSession(String atSign) {
    addSession(atSign); // Always ensure the session exists
    activeSession = atSign;
    windowOffset = sessionList.indexOf(atSign);
  }

  void addMessage(String atSign, String message, {bool incoming = false}) {
    addSession(atSign);
    final prefix = incoming ? chalk.green('$atSign: ') : chalk.blue('me: ');
    sessions[atSign]!.messages.add(prefix + message);
    if (activeSession != atSign) {
      // Optionally show notification for new message in inactive session
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

  void draw() {
    stdout.write('\x1b[2J\x1b[H'); // Clear screen
    stdout.writeln(chalk.bold('atTalk TUI - @${myAtSign}'));
    stdout.writeln('Sessions: ' + sessionList.asMap().entries.map((e) => e.key == windowOffset ? chalk.yellow('[${e.value}]') : e.value).join(' '));
    stdout.writeln('---');
    // Show all windows (panes)
    for (int i = 0; i < sessionList.length; i++) {
      var s = sessionList[i];
      stdout.writeln((i == windowOffset ? chalk.yellow('== $s ==') : '   $s'));
      for (var msg in sessions[s]!.messages.take(10)) {
        stdout.writeln(msg);
      }
      stdout.writeln('---');
    }
    stdout.writeln('Commands: /switch @other, /new @other, /next, /prev, /exit');
    stdout.write('> ');
  }

  Future<void> run() async {
    draw();
    var lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.startsWith('/switch ')) {
        var atSign = line.substring(8).trim();
        switchSession(atSign);
        windowOffset = sessionList.indexOf(atSign);
      } else if (line.startsWith('/new ')) {
        var atSign = line.substring(5).trim();
        addSession(atSign);
        switchSession(atSign);
        windowOffset = sessionList.indexOf(atSign);
      } else if (line == '/next') {
        nextWindow();
      } else if (line == '/prev') {
        prevWindow();
      } else if (line == '/exit') {
        break;
      } else if (activeSession != null) {
        addMessage(activeSession!, line);
        if (onSend != null) {
          onSend!(activeSession!, line);
        }
      }
      draw();
    }
  }
}

// To use this, instantiate TuiChatApp in your main and call run().
// You will need to integrate message sending/receiving with your atTalk logic.
