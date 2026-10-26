# Copie locale de record_windows 1.0.7

Copie du paquet pub.dev `record_windows` 1.0.7, inchangee sauf une ligne :
`cmake_minimum_required(VERSION 3.23)` abaissee a 3.14 dans `windows/CMakeLists.txt`.

Raison : Visual Studio Build Tools 2019 fournit CMake 3.20 et le fichier n'utilise
aucune fonctionnalite au-dela de 3.14 (son propre commentaire le dit). Branchee via
`dependency_overrides` dans `pubspec.yaml`. A supprimer des que la machine de build
dispose de CMake >= 3.23 (Visual Studio 2022).
