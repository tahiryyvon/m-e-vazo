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

## Ajouts du 26 octobre

- Onglet « Écoute micro » : capture PCM (plugin `record`), accord + note dominante en direct (`LiveChordDetector`, `MicListenerService`, `MicListenScreen`). Sur Windows, copie locale du plugin dans `third_party/record_windows` (CMake 3.20 de VS 2019).
- Mobile portrait : paroles sur 50 % de la hauteur du lecteur, diagrammes des doigts fixes sous les pastilles (jamais masqués), tonalité/capo dans une bande défilante, contrôles compacts.
- Android/iOS : le curseur de volume pilote le volume média du système (`volume_controller`) et suit les touches physiques.
- Paroles : troisième niveau via description et commentaires YouTube.

## Audit sécurité / performance du 28 octobre

- Proxy audio local : jeton secret aléatoire dans l'URL, GET/HEAD uniquement, identifiant vidéo validé, délais d'attente, cache des flux borné (64 entrées, 15 min).
- Pages web tierces (paroles) : client `createPublicWebClient` qui n'accepte que HTTPS sur le port 443 vers des adresses IP publiques, connexion directe à l'IP vérifiée (pas de rebinding DNS), TLS validé contre le nom d'hôte, redirections bornées à 3 et revérifiées à chaque saut, corps limité à 2 Mo lu en flux.
- Correctif critique : la première version de ce client ouvrait un socket non chiffré vers le port 443, ce qui cassait toutes les recherches web de paroles. Il ouvre désormais un `SecureSocket` (vérifié en réel : Genius, GitHub).
- Téléchargements d'analyse et fichiers WAV limités à 256 Mo ; écritures disque en flux.
- `YoutubeService` : identifiants vidéo validés (ils servent dans des noms de fichiers), URL de flux expirées après 2 h et limitées à 64, cinq fichiers temporaires au plus sur disque.
- Micro : un découpage du flux sur un nombre impair d'octets ne décale plus les échantillons.
- Import de dossier plafonné (5 000 titres, 50 000 entrées parcourues) ; dossiers illisibles ignorés.
- Bibliothèque : écritures sérialisées, liste rendue paresseusement (tient des milliers de titres).
- Optimisation tentée puis abandonnée : réécriture de la boucle FFT de l'analyse d'accords. Résultat identique mais 33 % plus lente en mesure ; code d'origine conservé.

## Paroles des fichiers locaux (28 octobre)

- LRCLIB reste la première source pour tous les morceaux. Pour un fichier local, la recherche échouait toujours (artiste « Unknown Artist », pas de durée) et l'app passait directement aux sites web.
- Les tags ID3 (titre, artiste, durée) des MP3 sont lus avant la recherche (`AudioTagReader`). Les noms de fichiers sont nettoyés (numéros de piste, tirets bas, tirets longs).
- Sans artiste, LRCLIB cherche par titre seul et retient l'artiste majoritaire ; une durée connue filtre à ±5 s.
- Limite : un titre ambigu sans artiste peut tomber sur une autre version (ex. « La Vie en rose » en anglais). Les tags M4A/FLAC ne sont pas encore lus.

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
