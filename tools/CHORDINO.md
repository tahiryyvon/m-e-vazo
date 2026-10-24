# Windows chord analysis

Run `powershell -File tools/setup_chordino.ps1` before building Windows. CMake
copies the runtime into `data/chordino` beside the app. No system installation
or Python runtime is required. Downloads are pinned and SHA-256 checked.

Components and sources:

- Sonic Annotator 1.7, official Windows x64 binary and source:
  https://github.com/sonic-visualiser/sonic-annotator/releases/tag/sonic-annotator-1.7
- NNLS Chroma / Chordino 1.1, unofficial x64 build and reproducible build recipe:
  https://github.com/jotapemj/nnls-chroma-win64/tree/v1.1-win64
- Original algorithm documentation and source:
  https://isophonics.net/nnls-chroma

The runtime contains its original GPL license files. Preserve those files and
the upstream source references when packaging the app.

The app analyzes decoded WAV audio with NNLS + default HMM/Viterbi, retains
the resulting timestamps, and preserves N (no chord) gaps. The playing view
reduces extensions and inversions to major/minor shapes and merges adjacent
equivalent labels. Unsupported suspended, augmented, or diminished labels and
fragments shorter than 400 ms are left blank, not filled with the prior chord.
Capo remains a manual playing choice. This is an estimate, not a verified score.

Missing or failed native analysis never falls back to the experimental Dart
matcher on Windows. `analyzePcm` remains available for comparison tests.

Diagnostic audio and outputs live under ignored `build/diagnostics`; they must
not be committed. Reduced event count measures stability, not chord accuracy.
