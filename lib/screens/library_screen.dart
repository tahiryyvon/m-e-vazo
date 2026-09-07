import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import '../services/local_library_service.dart';

class LibraryScreen extends StatefulWidget {
  final Function(Song) onSongSelected;

  const LibraryScreen({super.key, required this.onSongSelected});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    LocalLibraryService.init();
  }

  Future<void> _pickFiles() async {
    setState(() => _isLoading = true);

    try {
      // On Android, ensure permissions are requested
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final audioStatus = await Permission.audio.status;
        if (!audioStatus.isGranted) {
          final res = await Permission.audio.request();
          if (!res.isGranted) {
            await Permission.storage.request();
          }
        }
      }

      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg', 'wma', 'opus'],
        );
      } catch (_) {
        // Fallback for devices where custom extensions throw
        result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.audio,
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final newSongs = result.files
            .where((f) => f.path != null && f.path!.isNotEmpty)
            .map((f) => Song.fromLocalFile(f.path!))
            .toList();

        if (newSongs.isNotEmpty) {
          await LocalLibraryService.addSongs(newSongs);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sélection : $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: ValueListenableBuilder<List<Song>>(
          valueListenable: LocalLibraryService.librarySongsNotifier,
          builder: (context, localSongs, _) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(localSongs.length)),
                SliverToBoxAdapter(child: _buildDemoTrackCard()),
                if (localSongs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  _buildListSliver(localSongs),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ma Bibliothèque',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Fichiers audio locaux avec accords & paroles synchronisés',
                      style: TextStyle(color: Color(0xFF777777), fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Add files button
              GestureDetector(
                onTap: _isLoading ? null : _pickFiles,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C00), Color(0xFFFF5500)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Ajouter',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Featured demo track card that plays immediately with 0 configuration
  Widget _buildDemoTrackCard() {
    final demoSong = LocalLibraryService.acousticDemoSong;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onSongSelected(demoSong),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF8C00).withValues(alpha: 0.18),
                  const Color(0xFF1E1E1E),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFF8C00).withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                // Guitar icon container
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C00), Color(0xFFFF5500)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                // Track details
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
                              'DÉMO INCLUSE',
                              style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ACCORDS G-Em-C-D',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        demoSong.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "M' e-Vazo Studio • 24s • Tonalité Sol (G)",
                        style: TextStyle(color: Color(0xFF999999), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Play button icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF8C00).withValues(alpha: 0.2),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Color(0xFFFF8C00), size: 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF181818),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 38,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Aucun fichier local pour le moment',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Appuyez sur "Ajouter" ou le bouton ci-dessous pour choisir\ndes morceaux MP3, WAV ou M4A sur votre appareil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickFiles,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8C00), Color(0xFFFF5500)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Parcourir mes fichiers audio',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListSliver(List<Song> songs) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = songs[index];
            return _LocalSongTile(
              song: song,
              onTap: () => widget.onSongSelected(song),
              onRemove: () => LocalLibraryService.removeSong(song.id),
            );
          },
          childCount: songs.length,
        ),
      ),
    );
  }
}

class _LocalSongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _LocalSongTile({
    required this.song,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8C00).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.audio_file_rounded,
                    color: Color(0xFFFF8C00),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: 0.3)),
                  tooltip: 'Supprimer',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
