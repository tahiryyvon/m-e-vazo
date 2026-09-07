import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/music_player_controller.dart';
import '../models/song.dart';
import 'search_screen.dart';
import 'player_screen.dart';
import 'library_screen.dart';
import '../widgets/mini_player.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MusicPlayerController _controller = MusicPlayerController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSongSelected(Song song) {
    setState(() => _currentIndex = 1);
    _controller.playSong(song);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      SearchScreen(onSongSelected: _onSongSelected, controller: _controller),
      PlayerScreen(controller: _controller),
      LibraryScreen(onSongSelected: _onSongSelected),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900 && constraints.maxHeight >= 550;
        final isCompactLandscape = constraints.maxWidth > constraints.maxHeight && !isDesktop;

        if (isDesktop) {
          return _buildWideLayout(screens);
        } else if (isCompactLandscape) {
          return _buildLandscapeNavRailLayout(screens);
        } else {
          return _buildMobileLayout(screens);
        }
      },
    );
  }

  /// Compact mobile landscape layout: Slim 60px icon rail on left + safe areas
  Widget _buildLandscapeNavRailLayout(List<Widget> screens) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: Container(
              width: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                border: Border(
                  right: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 1),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/acoustic_guitar_logo.jpg',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _NavRailIcon(
                    icon: Icons.search_rounded,
                    isSelected: _currentIndex == 0,
                    onTap: () => setState(() => _currentIndex = 0),
                  ),
                  const SizedBox(height: 4),
                  _NavRailIcon(
                    icon: Icons.music_note_rounded,
                    isSelected: _currentIndex == 1,
                    onTap: () => setState(() => _currentIndex = 1),
                  ),
                  const SizedBox(height: 4),
                  _NavRailIcon(
                    icon: Icons.library_music_rounded,
                    isSelected: _currentIndex == 2,
                    onTap: () => setState(() => _currentIndex = 2),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: screens,
            ),
          ),
        ],
      ),
    );
  }

  /// Wide desktop / tablet layout with left navigation rail
  Widget _buildWideLayout(List<Widget> screens) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Row(
        children: [
          // Left Sidebar Navigation
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              border: Border(
                right: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 1),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Brand Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF8C00).withValues(alpha: 0.35),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/acoustic_guitar_logo.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.queue_music_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "M' e-Vazo",
                              style: GoogleFonts.righteous(
                                color: Colors.white,
                                fontSize: 24,
                                letterSpacing: 1.2,
                                shadows: [
                                  const Shadow(
                                    color: Color(0xFFFF8C00),
                                    offset: Offset(1.5, 1.5),
                                    blurRadius: 0,
                                  ),
                                  const Shadow(
                                    color: Color(0xFFB84500),
                                    offset: Offset(3.0, 3.0),
                                    blurRadius: 0,
                                  ),
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.85),
                                    offset: const Offset(4.5, 4.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Nav items
                  _SidebarItem(
                    icon: Icons.search_rounded,
                    label: 'Discover',
                    isSelected: _currentIndex == 0,
                    onTap: () => setState(() => _currentIndex = 0),
                  ),
                  _SidebarItem(
                    icon: Icons.music_note_rounded,
                    label: 'Player',
                    isSelected: _currentIndex == 1,
                    onTap: () => setState(() => _currentIndex = 1),
                  ),
                  _SidebarItem(
                    icon: Icons.library_music_rounded,
                    label: 'My Library',
                    isSelected: _currentIndex == 2,
                    onTap: () => setState(() => _currentIndex = 2),
                  ),

                  const Spacer(),

                  // Mini player in sidebar when not on player screen
                  if (_currentIndex != 1)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: MiniPlayer(
                        controller: _controller,
                        onTap: () => setState(() => _currentIndex = 1),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Main Screen Content
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: screens,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact mobile layout with bottom navigation bar
  Widget _buildMobileLayout(List<Widget> screens) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only show mini player when NOT already on player tab
          if (_currentIndex != 1)
            MiniPlayer(
              controller: _controller,
              onTap: () => setState(() => _currentIndex = 1),
            ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 1),
              ),
            ),
            child: SafeArea(
              top: false,
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) => setState(() => _currentIndex = index),
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: const Color(0xFFFF8C00),
                unselectedItemColor: const Color(0xFF555555),
                selectedLabelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 11),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.search_rounded),
                    activeIcon: Icon(Icons.search_rounded),
                    label: 'Search',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.music_note_rounded),
                    activeIcon: Icon(Icons.music_note_rounded),
                    label: 'Player',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.library_music_rounded),
                    activeIcon: Icon(Icons.library_music_rounded),
                    label: 'Library',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFF8C00).withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.35))
            : null,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFFFF8C00) : const Color(0xFF777777),
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF888888),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 14,
          ),
        ),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }
}

class _NavRailIcon extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavRailIcon({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        color: isSelected ? const Color(0xFFFF8C00) : const Color(0xFF777777),
        size: 20,
      ),
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFFFF8C00).withValues(alpha: 0.15) : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(8),
      ),
    );
  }
}
