import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Prevents idle screen timeout, without waking or unlocking the device.
class ScreenAwakeService {
  static const channel = MethodChannel('me_vazo/screen_awake');
  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.windows)) {
      return;
    }
    try {
      await channel.invokeMethod<void>('setEnabled', enabled);
    } on PlatformException catch (error) {
      debugPrint('[ScreenAwake] $error');
    } on MissingPluginException catch (error) {
      debugPrint('[ScreenAwake] $error');
    }
  }
}
