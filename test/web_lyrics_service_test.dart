import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:guitar_lyrics_player/services/web_lyrics_service.dart';

const sample = '<title>Test Band – Test Song Lyrics</title>'
    '<div data-lyrics-container="true">An invented first line for this test<br>'
    'Another invented line, with &amp; punctuation</div>';

void main() {
  test('parses Genius lines without timestamps and preserves source', () {
    final uri = Uri.parse('https://genius.com/test-song-lyrics');
    final lines = WebLyricsService.parsePage(sample, uri, 'Test Song', 'Test Band')!;
    expect(lines.length, 2);
    expect(lines.last.text, contains('& punctuation'));
    expect(lines.every((line) => !line.isSynced && line.sourceUrl == uri), isTrue);
    expect(WebLyricsService.parsePage(sample, uri, 'Other Song', 'Test Band'), isNull);
  });
  test('prefers Genius and tries another supported source on refusal', () async {
    final requests = <Uri>[];
    final service = WebLyricsService(client: MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'www.google.com') {
        return http.Response('<a href="/url?q=https%3A%2F%2Fgenius.com%2Ftest-lyrics">G</a>'
            '<a href="https://www.paroles.net/test-song">P</a>', 200);
      }
      if (request.url.host == 'genius.com') return http.Response('Forbidden', 403);
      return http.Response(sample.replaceAll('data-lyrics-container="true"', 'class="song-text"'), 200,
          headers: {'content-type': 'text/html; charset=utf-8'});
    }));
    addTearDown(service.dispose);
    final lines = await service.search('Test Song', 'Test Band', isCurrent: () => true);
    expect(requests[1].host, 'genius.com');
    expect(lines!.first.sourceUrl!.host, 'www.paroles.net');
  });
  test('does not fetch a stale song or arbitrary search URLs', () async {
    final service = WebLyricsService(client: MockClient((request) async =>
        throw StateError('Must not request a cancelled song')));
    addTearDown(service.dispose);
    expect(await service.search('Test', 'Band', isCurrent: () => false), isNull);
    expect(WebLyricsService.resultLinks('<a href="https://genius.com.evil.test/a">bad</a>'
        '<a href="http://127.0.0.1/a">local</a>'), isEmpty);
  });
  test('search refusal produces no fabricated lyrics', () async {
    final service = WebLyricsService(client: MockClient((_) async => http.Response('Blocked', 429)));
    addTearDown(service.dispose);
    expect(await service.search('Test', 'Band', isCurrent: () => true), isNull);
  });

  test('decodes DuckDuckGo redirectors, drops media sites, ranks known lyrics hosts first', () {
    final links = WebLyricsService.resultLinks(
        '<a href="https://www.youtube.com/watch?v=1">yt</a>'
        '<a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample-lyrics.org%2Ftest-song&amp;rut=1">d</a>'
        '<a href="https://genius.com/test-lyrics#about">g</a>'
        '<a href="https://genius.com/test-lyrics">dup</a>'
        '<a href="https://cdn.example-lyrics.org/cover.jpg">img</a>');
    expect(links.map((u) => u.toString()).toList(),
        ['https://genius.com/test-lyrics', 'https://example-lyrics.org/test-song']);
  });
  test('generic extraction picks the block of short lines on an unknown site', () {
    final page = '<html><head><title>Test Song - Test Band | Example Lyrics</title></head><body>'
        '<nav><a href="/">Home</a><a href="/a">Artists</a><a href="/b">Albums</a>'
        '<a href="/c">Charts</a><a href="/d">News</a><a href="/e">About</a>'
        '<a href="/f">Contact</a><a href="/g">Login</a><a href="/h">More</a></nav>'
        '<h1>Test Song</h1><p>This long editorial paragraph talks about the song, the band, '
        'the album release, the producers, the chart positions and a lot of other things '
        'that are definitely not the lyrics themselves and should never be selected.</p>'
        '<div class="main"><div class="txt">'
        '${List.generate(12, (i) => 'Invented lyric line number $i').join('<br>')}'
        '</div><div class="comments"><p>Great song!</p><p>Love it</p></div></div>'
        '<footer>© Example</footer></body></html>';
    final uri = Uri.parse('https://example-lyrics.org/test-band/test-song');
    final lines = WebLyricsService.parsePage(page, uri, 'Test Song', 'Test Band')!;
    expect(lines.length, 12);
    expect(lines.first.text, 'Invented lyric line number 0');
    expect(lines.last.text, 'Invented lyric line number 11');
    expect(lines.every((l) => !l.isSynced && l.sourceUrl == uri), isTrue);
    // A page about another song is rejected even if it has a lyrics-shaped block.
    expect(WebLyricsService.parsePage(page, uri, 'Completely Different', 'Someone'), isNull);
  });
  test('falls through the engines and opens the first result when Google refuses', () async {
    final requests = <Uri>[];
    final service = WebLyricsService(client: MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'www.google.com') return http.Response('Blocked', 429);
      if (request.url.host == 'www.bing.com') {
        return http.Response('<rss><item><link>https://genius.com/test-lyrics</link></item></rss>', 200);
      }
      return http.Response(sample, 200, headers: {'content-type': 'text/html; charset=utf-8'});
    }));
    addTearDown(service.dispose);
    final lines = await service.search('Test Song', 'Test Band', isCurrent: () => true);
    expect(requests.map((u) => u.host).toList(),
        ['www.google.com', 'html.duckduckgo.com', 'www.bing.com', 'genius.com']);
    expect(lines, isNotNull);
    expect(lines!.length, 2);
  });
}
