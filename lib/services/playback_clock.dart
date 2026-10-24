/// Interpolates coarse player positions with a monotonic clock.
/// Extrapolation is bounded so a stalled native player cannot drift indefinitely.
class PlaybackClock {
  Duration _position = Duration.zero;
  Duration _anchorTime = Duration.zero;
  bool _advancing = false;

  Duration positionAt(Duration now) {
    if (!_advancing) return _position;
    final elapsed = (now - _anchorTime).inMicroseconds.clamp(0, 250000);
    return _position + Duration(microseconds: elapsed);
  }

  void anchor(Duration position, Duration now) {
    _position = position;
    _anchorTime = now;
  }

  void setAdvancing(bool advancing, Duration now) {
    if (_advancing == advancing) return;
    _position = positionAt(now);
    _anchorTime = now;
    _advancing = advancing;
  }
}
