# Handoff — M'e-Vazo (25 octobre 2026)

## État

- Branche `main`, arbre de travail propre. Derniers commits :
  - `7d406fc` feat(platforms) : version Web testée, fichiers locaux navigateur, plein écran, raccourcis clavier, barré sur les diagrammes.
  - `11b1b77` feat(lyrics) : repli web des paroles, lecture non bloquante, durcissement réseau Android.
- `flutter analyze` : aucun problème. `flutter test` : 51 tests verts.
- Artefacts release compilés depuis `7d406fc` :
  - Android : `build/app/outputs/flutter-apk/app-release.apk` (signé avec la clé debug).
  - Windows : `build/windows/x64/runner/Release/` (exe + `data/` + DLL media_kit).
  - Web : `build/web/` (servir en statique, par ex. `python -m http.server 8765 --directory build/web`).

## Ce qui a été vérifié

- Web dans un vrai navigateur : accueil, bibliothèque, lecture de la démo avec accords et paroles synchronisés, aucune erreur console. Le bouton « Plein écran » est en bas à droite.
- Repli web des paroles (hors Web) : LRCLIB puis Google → DuckDuckGo → Bing, première page pertinente, texte non synchronisé avec lien source. Google renvoie une page « JavaScript requis » aux clients non navigateur : DuckDuckGo et Bing prennent le relais.
- Troisième niveau (hors Web) : description puis commentaires de la vidéo YouTube (`YoutubeLyricsService` + `LyricsTextExtractor`). Pour un fichier local, la vidéo est d'abord cherchée sur YouTube. Facebook et les autres réseaux ne sont pas lisibles sans connexion ; non implémentés. Limite connue : certaines pages de commentaires font planter le parseur de `youtube_explode_dart` (FormatException sur le nombre de likes) ; l'app renvoie alors simplement « pas de paroles ».
- Les paroles ne bloquent plus le démarrage de la lecture ; un morceau démarre même sans accords.

## Limites connues

- **Web** : recherche YouTube et repli web des paroles bloqués par CORS dans le navigateur (message affiché, bouton « Rechercher sur le Web » ouvre Google). Pas d'analyse d'accords audio sur Web. Fichiers importés valables uniquement pour la session (URL blob).
- **Windows** : l'application se lance en plein écran (canal `me_vazo/window`, méthodes `toggleFullscreen` / `exitFullscreen`).
- **Android** : barres système masquées (immersif), trafic HTTP en clair limité à `127.0.0.1` (proxy audio local). APK signé en debug : ajouter une vraie clé pour une publication.
- Les moteurs de recherche limitent le débit après de nombreuses requêtes rapprochées (observé pendant les tests).

## Pistes suivantes

1. Sur Web : passer la recherche YouTube par une API acceptant CORS (ex. instance Piped) ou un petit proxy maison.
2. Signer l'APK release et renseigner `applicationId` définitif.
3. Décider si le plein écran forcé au lancement sur Windows doit rester ou devenir un réglage.
4. Chords sur Web : porter l'analyse chroma en isolate web (Web Worker) si besoin.
