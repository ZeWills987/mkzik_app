#!/usr/bin/env bash
# Génère les notes de version (Markdown) à partir des commits conventionnels
# (feat/fix/style/refactor/perf) entre le dernier tag de version (vX.Y.Z) et
# HEAD. Utilisé par .github/workflows/android.yml et ios.yml pour remplir la
# description de chaque Release GitHub à tag fixe (android-latest/ios-latest).
#
# Nécessite un historique complet (fetch-depth: 0) pour voir les tags/commits.
set -euo pipefail

current_tag=$(git describe --tags --exact-match --match 'v*' HEAD 2>/dev/null || true)
prev_tag=$(git tag --list 'v*' --sort=-v:refname | grep -vx "$current_tag" | head -n1 || true)

if [ -n "$prev_tag" ]; then
  range="$prev_tag..HEAD"
else
  # Pas de tag précédent (premier build) → on se limite aux derniers commits.
  range="-n 25"
fi

# $1 = motif d'ancrage du type conventionnel (ex: '^feat[(:]')
commits() {
  git log $range --no-merges --pretty=format:'%s' \
    | grep -E "$1" \
    | sed -E 's/^[a-z]+(\([^)]*\))?: ?//' \
    | sed -E 's/ *\[(build|android|ios)\]//g' \
    | sed -E 's/^/- /'
}

feats=$(commits '^feat[(:]' || true)
fixes=$(commits '^fix[(:]' || true)
improvements=$(commits '^(style|refactor|perf)[(:]' || true)

printed=0

if [ -n "$feats" ]; then
  echo "## ✨ Nouveautés"
  echo "$feats"
  echo
  printed=1
fi

if [ -n "$fixes" ]; then
  echo "## 🐛 Corrections"
  echo "$fixes"
  echo
  printed=1
fi

if [ -n "$improvements" ]; then
  echo "## 🎨 Améliorations"
  echo "$improvements"
  echo
  printed=1
fi

if [ "$printed" -eq 0 ]; then
  echo "Améliorations et corrections diverses."
fi
