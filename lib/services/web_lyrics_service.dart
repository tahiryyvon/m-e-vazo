import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';
import 'public_web_client.dart';

/// Best-effort public-page lookup used when LRCLIB has nothing.
///
/// Strategy: ask web search engines (Google first, then DuckDuckGo's HTML
/// endpoint and Bing's RSS feed, since Google answers most non-browser
/// clients with a JavaScript-only page), open the first plausible result
/// pages and extract the lyrics block. Known lyrics sites use a precise CSS
/// selector; any other result page goes through a generic "block of many
/// short lines" heuristic. The result is unsynchronized (all timestamps
/// zero) but at least the text is displayed.
///
/// No CAPTCHA, login, consent or paywall bypass: a refusal yields null.
class WebLyricsService {
  final http.Client _client;
  WebLyricsService({http.Client? client}) : _client = client ?? createPublicWebClient();
  void dispose() => _client.close();

  static const Duration _requestTimeout = Duration(seconds: 6);
  static const Duration _totalBudget = Duration(seconds: 40);
  static const int _maxPagesPerEngine = 4;
  static const int _maxPagesTotal = 8;
  static const int _maxBodyBytes = 2000000;

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Google search page for [title] / [artist]; also used by the UI button.
  static Uri searchUrl(String title, String artist, {bool genius = false}) =>
      Uri.https('www.google.com', '/search', {
        'q': '"$title" "$artist" lyrics${genius ? ' site:genius.com' : ''}',
      });

  static bool _hasArtist(String artist) {
    final a = artist.trim().toLowerCase();
    return a.isNotEmpty && a != 'unknown artist';
  }

  /// Strict query (quoted) then a loose one when nothing comes back.
  static List<String> _queries(String title, String artist) {
    final t = title.trim();
    final a = artist.trim();
    final withArtist = _hasArtist(a);
    return [
      '"$t"${withArtist ? ' "$a"' : ''} lyrics',
      '$t${withArtist ? ' $a' : ''} paroles lyrics',
    ];
  }

  /// Hosts that failed (timeout, connection error) during this search are
  /// not retried: a hanging site must not burn the whole time budget.
  final Set<String> _deadHosts = {};

  Future<String?> _get(Uri uri) async {
    if (_deadHosts.contains(uri.host)) return null;
    try {
      // Redirects are safe to follow: every hop opens a new connection through
      // the public client's factory, which re-checks HTTPS and public IPs.
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 3;
      request.headers.addAll({
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
      });
      final response = await _client.send(request).timeout(_requestTimeout);
      if (response.statusCode != 200 || (response.contentLength ?? 0) > _maxBodyBytes) {
        // Drain by cancelling, not buffering a rejected or redirected page.
        await response.stream.listen((_) {}).cancel();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      final elapsed = Stopwatch()..start();
      await for (final chunk in response.stream.timeout(_requestTimeout)) {
        if (bytes.length + chunk.length > _maxBodyBytes || elapsed.elapsed > _requestTimeout) {
          return null;
        }
        bytes.add(chunk);
      }
      return _decodeBody(http.Response.bytes(bytes.takeBytes(), response.statusCode,
          headers: response.headers));
    } catch (e) {
      debugPrint('[WebLyricsService] GET ${uri.host} failed: $e');
      _deadHosts.add(uri.host);
      return null;
    }
  }

  /// Many lyrics sites serve UTF-8 without declaring a charset, which the
  /// http package would decode as Latin-1 (mojibake on accents).
  static String _decodeBody(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('charset=')) return response.body;
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException {
      return response.body;
    }
  }

  /// Searches the web and returns the first usable page's lyrics, or null.
  Future<List<LyricLine>?> search(String title, String artist,
      {required bool Function() isCurrent}) async {
    final started = DateTime.now();
    bool alive() =>
        isCurrent() && DateTime.now().difference(started) < _totalBudget;
    _deadHosts.clear();

    final titleWords = _keywords(title).toSet();
    final artistWords = _hasArtist(artist) ? _keywords(artist).toSet() : <String>{};
    final visited = <Uri>{};
    var pagesOpened = 0;

    for (final query in _queries(title, artist)) {
      var anyCandidate = false;
      for (final engine in _engines) {
        if (!alive()) return null;
        final links = await _searchEngine(engine, query);
        if (!alive()) return null;
        // Only open pages whose address already looks like this song's
        // lyrics: this keeps dictionaries and forums from eating the budget.
        final candidates = links
            .where((url) => _urlLooksRelevant(url, titleWords, artistWords))
            .toList();
        debugPrint('[WebLyricsService] $engine: ${links.length} results, '
            '${candidates.length} plausible'
            '${candidates.isEmpty ? '' : ' (first: ${candidates.first.host})'}');
        if (candidates.isNotEmpty) anyCandidate = true;

        var openedHere = 0;
        for (final url in candidates) {
          if (openedHere >= _maxPagesPerEngine) break;
          if (pagesOpened >= _maxPagesTotal) return null;
          if (_deadHosts.contains(url.host) || !visited.add(url)) continue;
          if (!alive()) return null;
          openedHere++;
          pagesOpened++;
          final body = await _get(url);
          if (!alive()) return null;
          if (body == null) continue;
          final lines = parsePage(body, url, title, artist);
          if (lines != null) {
            debugPrint('[WebLyricsService] Lyrics from ${url.host} (${lines.length} lines)');
            return lines;
          }
        }
      }
      // The loose query only helps when the strict one matched nothing.
      if (anyCandidate) return null;
    }
    return null;
  }

  // ── Search engines ──────────────────────────────────────────────────

  static const _engines = ['google', 'duckduckgo', 'bing'];

  Future<List<Uri>> _searchEngine(String engine, String query) async {
    switch (engine) {
      case 'google':
        // Google answers most non-browser clients with a page that requires
        // JavaScript; then no link is found and the next engines take over.
        final page = await _get(
          Uri.https('www.google.com', '/search', {'q': query, 'hl': 'fr', 'num': '10'}),
        );
        return page == null ? const [] : resultLinks(page);
      case 'duckduckgo':
        final page = await _get(
          Uri.https('html.duckduckgo.com', '/html/', {'q': query}),
        );
        return page == null ? const [] : resultLinks(page);
      case 'bing':
        final feed = await _get(
          Uri.https('www.bing.com', '/search', {'q': query, 'format': 'rss'}),
        );
        if (feed == null) return const [];
        final anchors = RegExp(r'<link>(.*?)</link>', dotAll: true)
            .allMatches(feed)
            .map((m) => '<a href="${m[1]!.trim()}">r</a>')
            .join();
        return resultLinks(anchors);
    }
    return const [];
  }

  // ── Result link extraction ──────────────────────────────────────────

  /// Hosts that are search engines or never host lyrics as readable text.
  static const _ignoredHostSuffixes = [
    'google.com', 'google.fr', 'googleusercontent.com', 'gstatic.com',
    'bing.com', 'microsoft.com', 'live.com', 'duckduckgo.com',
    'youtube.com', 'youtu.be', 'spotify.com', 'apple.com', 'amazon.com',
    'amazon.fr', 'deezer.com', 'soundcloud.com', 'facebook.com',
    'instagram.com', 'tiktok.com', 'twitter.com', 'x.com', 'pinterest.com',
    'wikipedia.org', 'wikimedia.org', 'discogs.com', 'shazam.com',
    'reddit.com', 'quora.com',
  ];

  static const _blockedTlds = ['test', 'local', 'localhost', 'invalid', 'example', 'internal'];
  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  static bool _hostAllowed(String host) {
    if (host.isEmpty) return false;
    if (_ipv4.hasMatch(host) || host.contains(':') || host.startsWith('[')) return false;
    final labels = host.split('.');
    if (labels.length < 2) return false;
    if (_blockedTlds.contains(labels.last)) return false;
    for (final suffix in _ignoredHostSuffixes) {
      if (host == suffix || host.endsWith('.$suffix')) return false;
    }
    return true;
  }

  static bool _looksLikeDocument(Uri url) {
    final path = url.path.toLowerCase();
    const binary = ['.pdf', '.jpg', '.jpeg', '.png', '.gif', '.mp3', '.mp4', '.zip', '.svg', '.webp'];
    return !binary.any(path.endsWith);
  }

  static const _lyricWords = ['lyrics', 'lyric', 'paroles', 'parole', 'letra', 'letras',
    'songtext', 'testo', 'tononkira', 'chanson', 'song'];

  /// A result is worth opening when it is a known lyrics site, or when its
  /// address mentions lyrics, or when it names the song itself.
  static bool _urlLooksRelevant(Uri url, Set<String> titleWords, Set<String> artistWords) {
    if (_selectorFor(url.host.toLowerCase()) != null) return true;
    final address = _normalize('${url.host} ${Uri.decodeComponent(url.path)}');
    final words = address.split(' ').toSet();
    if (_lyricWords.any(words.contains)) return true;
    final titleHits = titleWords.where(words.contains).length;
    if (titleWords.isNotEmpty && titleHits >= (titleWords.length / 2).ceil()) return true;
    return artistWords.isNotEmpty && artistWords.every(words.contains) && titleHits > 0;
  }

  /// Extracts candidate result URLs from a search engine page. Known lyrics
  /// sites come first (Genius before others), then other https results in
  /// page order. Only public https hosts are returned.
  static List<Uri> resultLinks(String body) {
    final seen = <String>{};
    final known = <Uri>[];
    final other = <Uri>[];
    for (final anchor in html.parse(body).querySelectorAll('a[href]')) {
      var url = Uri.tryParse(anchor.attributes['href']!.trim());
      if (url == null) continue;
      // Google "/url?q=" and DuckDuckGo "/l/?uddg=" redirectors.
      if (url.path == '/url' && (!url.hasAuthority || url.host.endsWith('google.com'))) {
        url = Uri.tryParse(url.queryParameters['q'] ?? url.queryParameters['url'] ?? '');
      } else if (url.path.startsWith('/l/') &&
          (!url.hasAuthority || url.host.endsWith('duckduckgo.com'))) {
        url = Uri.tryParse(url.queryParameters['uddg'] ?? '');
      }
      if (url == null || url.scheme != 'https' || url.userInfo.isNotEmpty) continue;
      final host = url.host.toLowerCase();
      if (!_hostAllowed(host) || !_looksLikeDocument(url)) continue;
      final clean = url.removeFragment();
      if (!seen.add(clean.toString())) continue;
      (_selectorFor(host) != null ? known : other).add(clean);
    }
    known.sort((a, b) => _rank(a.host).compareTo(_rank(b.host)));
    return [...known, ...other];
  }

  static int _rank(String host) => host.contains('genius.com') ? 0 : 1;

  // ── Page parsing ────────────────────────────────────────────────────

  static const _selectors = {
    'genius.com': '[data-lyrics-container="true"], .lyrics',
    'paroles.net': '.song-text',
    'paroles-musique.com': '#lyrics',
    'paroles2chansons.com': '.song-text, .lyrics',
    'paroles2chansons.lemonde.fr': '.song-text, .lyrics',
    'lyrics.com': '#lyric-body-text',
    'azlyrics.com': '.col-xs-12.col-lg-8.text-center > div:not([class])',
    'musixmatch.com': '[class*="lyrics__content"], .mxm-lyrics__content',
    'letras.com': '.lyric-original, .cnt-letra',
    'letras.mus.br': '.lyric-original, .cnt-letra',
    'songlyrics.com': '#songLyricsDiv',
    'lyricsmode.com': '#lyrics_text',
    'lyricstranslate.com': '#song-body, .song-node-text',
    'lyricsfreak.com': '.lyrictxt',
    'greatsong.net': '.lyrics, #lyrics',
    'lacoccinelle.net': '.lyrics',
    'lyricsmania.com': '.lyrics-body',
    'lyricfind.com': '.lyrics',
    'tononkira.serasera.org': '.tononkira, article',
  };

  static String? _selectorFor(String host) {
    final bare = host.replaceFirst('www.', '');
    for (final entry in _selectors.entries) {
      if (bare == entry.key || bare.endsWith('.${entry.key}')) return entry.value;
    }
    return null;
  }

  static String _normalize(String text) {
    var value = text.toLowerCase();
    const accents = {'é':'e','è':'e','ê':'e','ë':'e','à':'a','â':'a','ä':'a',
      'î':'i','ï':'i','ô':'o','ö':'o','ù':'u','û':'u','ü':'u','ç':'c','ñ':'n',
      'œ':'oe','æ':'ae','’':' ',"'":' '};
    accents.forEach((from, to) => value = value.replaceAll(from, to));
    return value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static const _stopWords = {
    'the', 'a', 'an', 'of', 'and', 'le', 'la', 'les', 'de', 'du', 'des', 'et',
    'un', 'une', 'en', 'feat', 'ft', 'official', 'video', 'lyrics', 'paroles',
    'remix', 'version', 'live', 'audio', 'hd', 'clip', 'officiel', 'officielle',
  };

  static List<String> _keywords(String text) => _normalize(text)
      .split(' ')
      .where((w) => w.length >= 2 && !_stopWords.contains(w))
      .toList();

  /// Fraction of [name]'s keywords present in [haystack] (0..1).
  static double _coverage(String name, Set<String> haystack) {
    final words = _keywords(name);
    if (words.isEmpty) return 1;
    final hits = words.where(haystack.contains).length;
    return hits / words.length;
  }

  /// Parses a lyrics page. Returns null when the page clearly is not about
  /// [title] or when no plausible lyrics block is found.
  static List<LyricLine>? parsePage(String body, Uri source, String title, String artist) {
    final document = html.parse(body);
    final identityText = [
      document.querySelector('title')?.text ?? '',
      document.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '',
      ...document.querySelectorAll('h1, h2').map((e) => e.text),
      Uri.decodeComponent(source.path).replaceAll(RegExp(r'[-_/.]+'), ' '),
    ].join(' ');
    final identity = _normalize(identityText).split(' ').toSet();

    final titleCoverage = _coverage(title, identity);
    final artistCoverage = _hasArtist(artist) ? _coverage(artist, identity) : 1.0;
    final selector = _selectorFor(source.host.toLowerCase());
    // Known lyrics sites: most title words must appear; unknown sites (any
    // first search result) need a stronger match since nothing else vouches
    // for them. In both cases the artist must appear unless the title is exact.
    final threshold = selector != null ? 0.6 : 0.75;
    if (titleCoverage < threshold || (titleCoverage < 1 && artistCoverage == 0)) {
      debugPrint('[WebLyricsService] ${source.host}: not this song '
          '(title ${(titleCoverage * 100).round()}%, artist ${(artistCoverage * 100).round()}%)');
      return null;
    }

    String? text;
    if (selector != null) {
      final containers = document.querySelectorAll(selector);
      if (containers.isNotEmpty) {
        text = containers.map(_blockText).join('\n\n');
      }
    }
    text ??= _genericLyricsBlock(document);
    if (text == null) {
      debugPrint('[WebLyricsService] ${source.host}: no lyrics block found');
      return null;
    }

    final lines = _cleanLines(text, title);
    final filled = lines.where((l) => l.isNotEmpty).length;
    final total = lines.fold<int>(0, (n, l) => n + l.length);
    final minLines = selector != null ? 2 : 8;
    if (filled < minLines || total < 40 || total > 50000) {
      debugPrint('[WebLyricsService] ${source.host}: block rejected ($filled lines, $total chars)');
      return null;
    }
    return lines
        .map((line) => LyricLine(
              timestamp: Duration.zero, text: line, isSynced: false, sourceUrl: source,
            ))
        .toList();
  }

  static const _junkSelector =
      'script, style, button, iframe, noscript, svg, form, select, input, '
      '[aria-hidden="true"], .ad, .ads, [class*="advert"], [id*="advert"], '
      // Genius: translations list and "<Title> Lyrics" header share the container.
      '[data-exclude-from-selection="true"], [class*="LyricsHeader"], '
      '[class*="Translation"]';
  static const _blockTags = {
    'p', 'div', 'li', 'h1', 'h2', 'h3', 'h4', 'section', 'article', 'pre',
    'blockquote', 'tr', 'td', 'ul', 'ol',
  };
  static const _skipTags = {
    'script', 'style', 'button', 'iframe', 'noscript', 'svg', 'form', 'select',
    'input', 'nav', 'header', 'footer', 'aside', 'template',
  };
  static final _sourceNewlines = RegExp(r'\s*\n\s*');

  /// Text of a container with <br> and block elements turned into newlines.
  /// Newlines of the HTML source itself are spaces (as in a browser), except
  /// inside <pre>, so only real line breaks produce lyric lines.
  static String _blockText(Element container) {
    final copy = container.clone(true);
    for (final junk in copy.querySelectorAll(_junkSelector)) {
      junk.remove();
    }
    final buffer = StringBuffer();
    void walk(Node node, bool pre) {
      if (node is Text) {
        buffer.write(pre ? node.text : node.text.replaceAll(_sourceNewlines, ' '));
        return;
      }
      if (node is! Element) return;
      final tag = node.localName ?? '';
      if (_skipTags.contains(tag)) return;
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
      final block = _blockTags.contains(tag);
      if (block) buffer.write('\n');
      for (final child in node.nodes) {
        walk(child, pre || tag == 'pre');
      }
      if (block) buffer.write('\n');
    }
    walk(copy, (container.localName ?? '') == 'pre');
    return buffer.toString();
  }

  static final _junkLine = RegExp(
    r'^(\d*\s*embed|you might also like|see .* live|get tickets as low as.*|'
    r'translations?|contributors?\d*|\d+ contributors?|lyrics|paroles( de la chanson)?|'
    r'print|imprimer|share|partager|copier|copy|corriger|submit corrections?|'
    r'advertisement|publicit[ée])$',
    caseSensitive: false,
  );

  static final _headerWords = RegExp(r'\b(lyrics|paroles|de la chanson|de|la|chanson|letra|songtext)\b');

  static List<String> _cleanLines(String text, String title) {
    final normalizedTitle = _normalize(title);
    bool isTitleHeader(String line) {
      final n = _normalize(line);
      if (n == normalizedTitle) return true;
      final stripped = n.replaceAll(_headerWords, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return stripped == normalizedTitle;
    }

    final out = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.replaceAll(RegExp(r'[ \t ]+'), ' ').trim();
      if (line.isEmpty) {
        if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
        continue;
      }
      if (_junkLine.hasMatch(line)) continue;
      // "<Title> Lyrics" / "Paroles de <Title>" headers above the text.
      if (out.where((l) => l.isNotEmpty).length < 3 && isTitleHeader(line)) continue;
      if (line.length > 300) continue; // prose paragraph, not a lyric line
      out.add(line);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    // One paragraph per line (or <br><br> everywhere) is not stanza
    // structure: drop the blanks when they alternate with almost every line.
    final blanks = out.where((l) => l.isEmpty).length;
    if (blanks > 0 && blanks >= (out.length - blanks) * 0.6) {
      out.removeWhere((l) => l.isEmpty);
    }
    return out;
  }

  /// Picks the element holding the largest block of short lines: lyrics are
  /// many consecutive short lines, unlike menus, comments or articles.
  /// Single bottom-up pass, so large pages stay cheap.
  static String? _genericLyricsBlock(Document document) {
    final body = document.body;
    if (body == null) return null;
    for (final junk in body.querySelectorAll(
        '$_junkSelector, nav, header, footer, aside, '
        '[role="navigation"], [role="banner"], [role="contentinfo"]')) {
      junk.remove();
    }

    final stats = <Element, _LineStats>{};
    _scan(body, stats, false);

    Element? best;
    var bestScore = double.negativeInfinity;
    var bestShort = 0;
    for (final element in body.querySelectorAll('div, section, article, pre, p, td, blockquote')) {
      final s = stats[element];
      if (s == null) continue;
      final short = s.totalShort;
      final long = s.totalLong;
      final lines = short + long;
      if (lines < 8) continue;
      if (short / lines < 0.85) continue;
      final avg = s.totalChars / lines;
      if (avg < 6 || avg > 70) continue;
      final score = (short - long * 4).toDouble();
      // A descendant keeping (almost) all the lines is a tighter container.
      final tighter = best != null && _isDescendant(element, best) && short >= bestShort * 0.8;
      if (score > bestScore || tighter) {
        best = element;
        bestScore = score;
        bestShort = short;
      }
    }
    if (best == null) return null;
    return _blockText(best);
  }

  static bool _isDescendant(Element element, Element ancestor) {
    for (Node? node = element.parent; node != null; node = node.parent) {
      if (identical(node, ancestor)) return true;
    }
    return false;
  }

  /// Counts short (2..90 chars) and long lines inside [element], where lines
  /// are separated by <br>, block boundaries and, inside <pre>, source
  /// newlines. Results are memoized per element: one pass over the document.
  static _LineStats _scan(Element element, Map<Element, _LineStats> memo, bool pre) {
    final stats = _LineStats();
    var current = 0;
    void flush() {
      if (current >= 2) {
        if (current <= 90) {
          stats.short++;
        } else {
          stats.long++;
        }
        stats.chars += current;
      }
      current = 0;
    }

    for (final node in element.nodes) {
      if (node is Text) {
        if (pre) {
          final parts = node.text.split('\n');
          for (var i = 0; i < parts.length; i++) {
            current += parts[i].trim().length;
            if (i < parts.length - 1) flush();
          }
        } else {
          current += node.text.replaceAll(_sourceNewlines, ' ').trim().length;
        }
      } else if (node is Element) {
        final tag = node.localName ?? '';
        if (_skipTags.contains(tag)) continue;
        if (tag == 'br') {
          flush();
          continue;
        }
        final child = _scan(node, memo, pre || tag == 'pre');
        final block = _blockTags.contains(tag);
        if (block || child.short + child.long > 0) {
          flush();
          stats.short += child.short;
          stats.long += child.long;
          stats.chars += child.chars;
        }
        current += child.inlineTail;
        if (block) flush();
      }
    }
    stats.inlineTail = current;
    memo[element] = stats;
    return stats;
  }
}

class _LineStats {
  int short = 0;
  int long = 0;
  int chars = 0;
  /// Characters after the last line break; they continue the parent's
  /// current line, so parents merge them separately from [short]/[long].
  int inlineTail = 0;

  // Totals including the trailing line, for evaluating the element itself.
  bool get _tailIsLine => inlineTail >= 2;
  int get totalShort => short + (_tailIsLine && inlineTail <= 90 ? 1 : 0);
  int get totalLong => long + (_tailIsLine && inlineTail > 90 ? 1 : 0);
  int get totalChars => chars + (_tailIsLine ? inlineTail : 0);
}
