# M' e-Vazo 🎸

> **Lecteur & Visualiseur d'Accords de Guitare Acoustique et Paroles Synchronisées**  
> *Cross-platform Flutter application for Windows & Android with real-time fretboard diagrams and synchronized lyrics.*

---

## 🌟 Présentation / Overview

**M' e-Vazo** est une application moderne et responsive conçue pour les musiciens, chanteurs et guitaristes. Elle permet d'écouter vos morceaux préférés (fichiers audio locaux ou morceau de démonstration intégré) tout en affichant les **paroles défilantes synchronisées** et les **diagrammes d'accords de guitare interactifs** avec le placement exact des doigts sur le manche en temps réel.

---

## ✨ Fonctionnalités Clés / Key Features

- 🎸 **Visualiseur d'Accords Interactif en Temps Réel** :
  - Rendu vectoriel dynamique de la touche de guitare (sillet, frettes, cordes, doigtés et cordes étouffées/ouvertes).
  - Affichage de l'accord courant (`CURRENT CHORD`) et aperçu anticipé de l'accord suivant (`NEXT CHORD`).
  - Palette complète des accords du morceau (`ALL CHORDS`) avec aperçu au survol/clic.

- ⏱️ **Moteur de Synchronisation & Anticipation Musicale (Zero-Latency)** :
  - **Anticipation naturelle (150 ms)** : Les diagrammes d'accords changent dès l'attaque du médiator sur le premier temps de chaque mesure, éliminant tout sentiment de retard dû aux buffers audio ou à la granularité des flux.
  - **Calibration manuelle fine (`SYNC +/-`)** : Ajustez le calage temporel des accords en temps réel par pas de 100 ms directement depuis l'interface du lecteur.

- 🎶 **Morceau de Démonstration Acoustique Intégré** :
  - Piste audio physique haute fidélité (`assets/audio/acoustic_demo.wav`, 24 secondes) générée par modélisation Karplus-Strong.
  - 100% autonome et hors-ligne, sans permission réseau requise.
  - Progression harmonique en 8 mesures (Sol Majeur / G $\rightarrow$ Mi Mineur / Em $\rightarrow$ Do Majeur / C $\rightarrow$ Ré Majeur / D) avec paroles synchronisées.

- 📁 **Bibliothèque Locale Persistante** :
  - Importez vos propres fichiers audio depuis votre appareil (**MP3, WAV, M4A, FLAC, AAC, OGG**).
  - Sauvegarde permanente de votre bibliothèque musicale via `SharedPreferences`.

- 🎧 **Historique des Dernières Chansons Lues** :
  - Sauvegarde automatique et accès rapide d'un clic aux morceaux récemment écoutés.

- 📱 **Interface Fluide & Entièrement Responsive** :
  - **Desktop / Écrans larges** : Navigation par barre latérale élégante avec typographie 3D, disposition double panneau (lecteur + accords à gauche, paroles défilantes à droite).
  - **Mobiles Paysage** : Rail d'icônes compact de 58 px optimisé pour garder un champ visuel maximal.
  - **Mobiles Portrait** : Navigation inférieure ergonomique avec mini-lecteur persistant lors de la navigation entre les onglets.

- 🎛️ **Bannière d'Informations Harmoniques** :
  - Détection automatique de la tonalité (`KEY`), du capo (`CAPO`) et de l'accordage (`TUNING`).

---

## 🛠️ Architecture & Stack Technique

- **Framework** : [Flutter](https://flutter.dev) (Dart 3)
- **Moteur Audio Windows Desktop** : `media_kit` (basé sur `libmpv` natif avec décodage matériel)
- **Moteur Audio Mobile (Android)** : `just_audio` (ExoPlayer natif avec gestion des flux d'arrière-plan)
- **Gestion d'état** : `ChangeNotifier` & `ValueNotifier` réactifs avec contrôleur centralisé (`MusicPlayerController`)
- **Polices & Design** : Google Fonts (`Righteous` pour l'identité visuelle 3D) & design sombre contrasté haute visibilité pour la scène
- **Services Métadonnées** :
  - Détection et parsing automatique des accords et tablatures
  - Synchronisation temporelle des paroles au format LRC

---

## 📁 Structure du Projet

```text
guitar_lyrics_player/
├── android/                   # Configuration et manifestes natifs Android
├── assets/
│   ├── audio/
│   │   └── acoustic_demo.wav  # Morceau audio de démonstration hors-ligne
│   └── images/                # Logos et icônes vectorielles / matricielles
├── lib/
│   ├── controllers/
│   │   └── music_player_controller.dart   # Moteur audio, sync accords/paroles
│   ├── models/
│   │   ├── chord_event.dart               # Modèle d'événement d'accord
│   │   ├── lyric_line.dart                # Modèle de ligne de paroles
│   │   └── song.dart                      # Modèle de chanson
│   ├── screens/
│   │   ├── home_screen.dart               # Shell principal, navigation responsive
│   │   ├── library_screen.dart            # Gestionnaire de fichiers locaux
│   │   ├── player_screen.dart             # Lecteur complet & visualiseur
│   │   └── search_screen.dart             # Découverte & dernières chansons lues
│   ├── services/
│   │   ├── local_audio_proxy.dart         # Proxy loopback multiplateforme
│   │   ├── local_audio_proxy_io.dart      # Serveur loopback streaming natif
│   │   ├── local_library_service.dart     # Persistance des morceaux locaux
│   │   ├── lrclib_service.dart            # Récupération des paroles synchronisées
│   │   ├── recently_played_service.dart   # Persistance des dernières écoutes
│   │   ├── songsterr_service.dart         # Dictionnaire d'accords & progressions
│   │   ├── windows_audio_player.dart      # Wrapper MediaKit pour Windows
│   │   └── youtube_service.dart           # Recherche et extraction audio
│   ├── utils/
│   │   └── title_parser.dart              # Nettoyage et extraction artiste / titre
│   ├── widgets/
│   │   ├── chord_diagram.dart             # Dessin vectoriel du manche de guitare
│   │   ├── harmonic_info_bar.dart         # Barre de statut harmonique & sync
│   │   ├── mini_player.dart               # Lecteur flottant persistant
│   │   ├── song_list_item.dart            # Tuile de chanson interactive
│   │   └── synced_lyrics_chords_view.dart # Vue défilante accords + paroles
│   └── main.dart                          # Point d'entrée de l'application
├── test/
│   └── widget_test.dart       # Tests unitaires et smoke tests
├── windows/                   # Configuration CMake et runner natif Windows
└── pubspec.yaml               # Dépendances et déclaration des assets
```

---

## 🚀 Installation & Exécution

### Prérequis
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version 3.19 ou supérieure recommandée)
- Pour Windows : Visual Studio (avec le composant « Desktop development with C++ »)
- Pour Android : Android Studio / Android SDK avec Java 17+

### 1. Cloner le Dépôt
```bash
git clone https://github.com/tahiryyvon/m-e-vazo.git
cd m-e-vazo
```

### 2. Installer les Dépendances
```bash
flutter pub get
```

### 3. Exécuter sur Windows (Desktop)
```bash
# Lancement en mode debug
flutter run -d windows

# Ou compiler le binaire Release
flutter build windows --release
# Le binaire se trouve dans : build\windows\x64\runner\Release\guitar_lyrics_player.exe
```

### 4. Exécuter sur Android
```bash
# Lancement sur votre appareil ou émulateur
flutter run -d android

# Ou compiler l'APK debug
flutter build apk --debug
# L'APK se trouve dans : build/app/outputs/flutter-apk/app-debug.apk
```

---

## 🧪 Tests & Analyse du Code

Pour vérifier la conformité du code et exécuter la suite de tests :

```bash
# Analyse statique sans aucun avertissement
flutter analyze

# Exécution des tests unitaires
flutter test
```

---

## 📄 Licence

Ce projet est sous licence MIT. Libre d'utilisation pour tout usage personnel ou éducatif.
