import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/music_player_controller.dart';

/// Keyboard controls shared by desktop, browser and mobile hardware keyboards.
class PlayerKeyboardControls extends StatelessWidget {
  final MusicPlayerController controller;
  final Widget child;
  const PlayerKeyboardControls(
      {super.key, required this.controller, required this.child});

  KeyEventResult _handle(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows &&
        (event.logicalKey == LogicalKeyboardKey.f11 ||
            event.logicalKey == LogicalKeyboardKey.escape)) {
      if (event is KeyDownEvent) {
        unawaited(const MethodChannel('me_vazo/window').invokeMethod<void>(
          event.logicalKey == LogicalKeyboardKey.f11 ? 'toggleFullscreen' : 'exitFullscreen',
        ));
      }
      return KeyEventResult.handled;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    // Do not control audio from an open menu or dialog.
    if (focused != null && ModalRoute.of(focused)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    if (controller.currentSong == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    Future<void> Function()? action;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      action = controller.togglePlayPause;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      action = controller.seekBackward;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      action = controller.seekForward;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      action = () =>
          controller.setVolume((controller.volume + 0.05).clamp(0.0, 1.0));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      action = () =>
          controller.setVolume((controller.volume - 0.05).clamp(0.0, 1.0));
    } else if (key == LogicalKeyboardKey.keyM) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      action = controller.toggleMute;
    } else if (key == LogicalKeyboardKey.home) {
      action = () => controller.seek(Duration.zero);
    }
    if (action == null) return KeyEventResult.ignored;
    unawaited(action());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _handle,
        child: child,
      );
}
