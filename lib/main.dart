import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit (required before using Player)
  MediaKit.ensureInitialized();

  // Initialize background audio service on supported mobile platforms
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.guitarlyrics.channel.audio',
        androidNotificationChannelName: "M' e-Vazo",
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidNotificationOngoing: true,
        preloadArtwork: true,
      );
    } catch (e) {
      debugPrint('JustAudioBackground init error: $e');
    }

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // Immersive dark status/nav bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0D0D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const GuitarLyricsPlayerApp());
}

class GuitarLyricsPlayerApp extends StatelessWidget {
  const GuitarLyricsPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "M' e-Vazo",
      debugShowCheckedModeBanner: false,
      theme: _buildDarkTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildDarkTheme() {
    const seedColor = Color(0xFFFF8C00); // Deep amber/orange
    const bgColor = Color(0xFF0D0D0D);
    const surfaceColor = Color(0xFF1A1A1A);
    const cardColor = Color(0xFF222222);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      surface: surfaceColor,
      onSurface: Colors.white,
    ).copyWith(
      surface: bgColor,
      onSurface: Colors.white,
      primaryContainer: cardColor,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgColor,
    );

    return base.copyWith(
      textTheme: GoogleFonts.outfitTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF111111),
        selectedItemColor: Color(0xFFFF8C00),
        unselectedItemColor: Color(0xFF666666),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Color(0xFFFF8C00),
        inactiveTrackColor: Color(0xFF333333),
        thumbColor: Color(0xFFFF8C00),
        overlayColor: Color(0x29FF8C00),
        trackHeight: 3,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF555555)),
      ),
    );
  }
}
