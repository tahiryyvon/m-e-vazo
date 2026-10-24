import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/playback_clock.dart';

Duration ms(int value) => Duration(milliseconds: value);

void main() {
  test('advances between native events and resynchronizes at each anchor', () {
    final clock = PlaybackClock();
    clock.anchor(ms(1000), ms(0));
    clock.setAdvancing(true, ms(0));
    expect(clock.positionAt(ms(80)), ms(1080));
    clock.anchor(ms(1090), ms(100));
    expect(clock.positionAt(ms(120)), ms(1110));
    expect(clock.positionAt(ms(5000)), ms(1340)); // bounded stale extrapolation
  });
  test('pause and buffering freeze time; resume and backward seek re-anchor', () {
    final clock = PlaybackClock();
    clock.anchor(ms(10000), ms(0));
    clock.setAdvancing(true, ms(0));
    clock.setAdvancing(false, ms(40));
    expect(clock.positionAt(ms(2000)), ms(10040));
    clock.setAdvancing(true, ms(2000));
    expect(clock.positionAt(ms(2020)), ms(10060));
    clock.setAdvancing(false, ms(2020));
    clock.anchor(ms(500), ms(2100));
    clock.setAdvancing(true, ms(2100));
    expect(clock.positionAt(ms(2120)), ms(520));
  });
}
