#!/bin/bash

# ── TrakNova APK Build Script ─────────────────────────────────────
set -e   # stop on first error

# Resolve Flutter – check common locations
if command -v flutter &>/dev/null; then
  FLUTTER="flutter"
elif [ -f "$HOME/flutter/bin/flutter" ]; then
  FLUTTER="$HOME/flutter/bin/flutter"
elif [ -f "$HOME/development/flutter/bin/flutter" ]; then
  FLUTTER="$HOME/development/flutter/bin/flutter"
else
  echo "❌  Flutter not found. Add Flutter to PATH and re-run."
  exit 1
fi

DART="$(dirname $(which $FLUTTER || echo $FLUTTER))/dart"
PROJECT="/Users/janidu/Documents/tracknova_mobile_app/Traknova-Mobile-App"

echo "📦  Flutter: $FLUTTER"
echo "📁  Project: $PROJECT"
cd "$PROJECT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 0/4 · Clean old build cache"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
$FLUTTER clean
rm -rf android/.gradle android/app/build

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 1/4 · flutter pub get"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
$FLUTTER pub get

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 2/4 · Generate app icons (TrakNova logo)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
$FLUTTER pub run flutter_launcher_icons || dart run flutter_launcher_icons

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 3/4 · flutter build apk --release"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
$FLUTTER build apk --release

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 4/4 · Copy APK → 'Traknova mobile app.apk'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cp build/app/outputs/flutter-apk/app-release.apk "Traknova mobile app.apk"

echo ""
echo "✅  Done!  APK saved to:"
echo "    $PROJECT/Traknova mobile app.apk"
