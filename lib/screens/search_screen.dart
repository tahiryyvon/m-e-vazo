import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../controllers/music_player_controller.dart';
import '../services/youtube_service.dart';
import '../services/recently_played_service.dart';
import '../services/local_library_service.dart';
import '../widgets/song_list_item.dart';

class SearchScreen extends StatefulWidget {
  final Function(Song) onSongSelected;
  final MusicPlayerController controller;

  const SearchScreen({
    super.key,
    required this.onSongSelected,
    required this.controller,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final YoutubeService _youtubeService = YoutubeService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Song> _results = [];
  bool _isLoading = false;
  String? _error;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    RecentlyPlayedService.init();
  }

  @override
  void dispose() {
    _youtubeService.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _focusNode.unfocus();

    setState(() {
      _isLoading = true;
      _error = null;
      _results = [];
      _hasSearched = true;
    });

    try {
      final results = await _youtubeService.searchSongs(q, maxResults: 20);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/images/acoustic_guitar_logo.jpg',
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8C00).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.music_note_rounded, color: Color(0xFFFF8C00)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "M' e-Vazo",
                      style: GoogleFonts.righteous(
                        color: Colors.white,
                        fontSize: 32,
                        letterSpacing: 1.4,
                        shadows: [
                          const Shadow(
                            color: Color(0xFFFF8C00),
                            offset: Offset(2.0, 2.0),
                            blurRadius: 0,
                          ),
                          const Shadow(
                            color: Color(0xFFB84500),
                            offset: Offset(4.0, 4.0),
                            blurRadius: 0,
                          ),
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.85),
                            offset: const Offset(6.0, 6.0),
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Paroles synchronisées & accords de guitare',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Input Bar
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? const Color(0xFFFF8C00).withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_rounded,
                  color: _focusNode.hasFocus
                      ? const Color(0xFFFF8C00)
                      : Colors.white.withValues(alpha: 0.35),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, or lyrics...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _performSearch,
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear_rounded, color: Colors.white.withValues(alpha: 0.4), size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _results = [];
                        _hasSearched = false;
                        _error = null;
                      });
                    },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(10),
                  ),
                GestureDetector(
                  onTap: () => _performSearch(_searchController.text),
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8C00), Color(0xFFFF5500)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Search',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildShimmer();
    if (_error != null) return _buildError();
    if (!_hasSearched) return _buildHomeContent();
    if (_results.isEmpty) return _buildEmpty();
    return _buildResults();
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF1E1E1E),
      highlightColor: const Color(0xFF2A2A2A),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 16),
            const Text('Search Failed', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF777777), fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _performSearch(_searchController.text),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text('No results found', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16)),
          const SizedBox(height: 8),
          Text('Try a different search term', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Morceau de démonstration officiel
              _buildDemoBanner(),

              const SizedBox(height: 12),

              // 2. SECTION: DERNIÈRES CHANSONS LUES (Recently Played Songs)
              _buildRecentlyPlayedSection(isWide),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDemoBanner() {
    final demoSong = LocalLibraryService.acousticDemoSong;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onSongSelected(demoSong),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF8C00).withValues(alpha: 0.2),
                  const Color(0xFF1E1610),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFF8C00).withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C00), Color(0xFFFF5500)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8C00).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'DÉMO MUSICALE',
                              style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Accords & Paroles synchronisés',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Écouter le morceau de démonstration',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFFF8C00), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentlyPlayedSection(bool isWide) {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: RecentlyPlayedService.recentSongsNotifier,
      builder: (context, recentSongs, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.play_circle_filled_rounded, size: 16, color: Color(0xFFFF8C00)),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'DERNIÈRES CHANSONS LUES',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (recentSongs.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${recentSongs.length}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (recentSongs.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        await RecentlyPlayedService.clearAll();
                      },
                      icon: Icon(Icons.delete_outline_rounded, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                      label: Text(
                        'Effacer tout',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ),
            if (recentSongs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161616),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Color(0xFFFF8C00), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Aucune chanson lue pour le moment',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Recherchez un titre ci-dessus ou ouvrez un fichier local pour commencer !',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              // Horizontal card carousel for recent songs
              SizedBox(
                height: 175,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: recentSongs.length,
                  itemBuilder: (context, index) {
                    final song = recentSongs[index];
                    return _RecentSongCard(
                      song: song,
                      isPlaying: widget.controller.currentSong?.id == song.id,
                      onTap: () => widget.onSongSelected(song),
                      onDelete: () => RecentlyPlayedService.removeSong(song.id),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }



  Widget _buildResults() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 680;

        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, child) {
            if (isWide) {
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 4.6,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 8,
                ),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final song = _results[index];
                  final isPlaying = widget.controller.currentSong?.id == song.id;
                  return SongListItem(
                    song: song,
                    onTap: () => widget.onSongSelected(song),
                    isPlaying: isPlaying,
                  );
                },
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final song = _results[index];
                final isPlaying = widget.controller.currentSong?.id == song.id;
                return SongListItem(
                  song: song,
                  onTap: () => widget.onSongSelected(song),
                  isPlaying: isPlaying,
                );
              },
            );
          },
        );
      },
    );
  }
}



class _RecentSongCard extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RecentSongCard({
    required this.song,
    required this.isPlaying,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 142,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPlaying
              ? const Color(0xFFFF8C00).withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.08),
          width: isPlaying ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (isPlaying)
            BoxShadow(
              color: const Color(0xFFFF8C00).withValues(alpha: 0.18),
              blurRadius: 10,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Artwork with badge & delete button
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        height: 84,
                        color: const Color(0xFF222222),
                        child: song.thumbnailUrl != null && !song.isLocal
                            ? CachedNetworkImage(
                                imageUrl: song.thumbnailUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: const Color(0xFF252525)),
                                errorWidget: (_, __, ___) => Container(
                                  color: const Color(0xFF252525),
                                  child: const Icon(Icons.music_note_rounded, color: Color(0xFFFF8C00), size: 30),
                                ),
                              )
                            : Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF381D08), Color(0xFF1F1510)],
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(Icons.music_note_rounded, color: Color(0xFFFF8C00), size: 30),
                                ),
                              ),
                      ),
                    ),

                    // Quick Play Icon Overlay (bottom-right of thumbnail)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    // Delete X button (top-right of thumbnail)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: onDelete,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 12, color: Colors.white70),
                        ),
                      ),
                    ),

                    // Source badge (Local / YouTube)
                    if (song.isLocal)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8C00).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'LOCAL',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                // Title
                Text(
                  song.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 2),

                // Artist
                Text(
                  song.artist,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
