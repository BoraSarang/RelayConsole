#!/bin/bash
# macOS 빌드 — Relay Console (버전은 Resources/Info.plist 단일 소스)
set -eo pipefail

APP_NAME="RelayConsole"
DISPLAY_NAME="Relay Console"
BUNDLE_ID="com.borasarang.relayconsole"
DEST_DIR="$HOME/Applications"
BUILD_DIR="./.build"

# 버전 단일 진실원처 — Info.plist 에서만 읽는다 (스크립트 하드코딩 금지)
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
[ -n "$VERSION" ] || { echo "Info.plist 버전 읽기 실패"; exit 1; }

# 서명 — Apple Development (비샌드박스 앱 · DECISIONS D2 로 위젯 appex 제거)
CODE_SIGN_IDENTITY="76811B50FF3F9015B9E287FC6829806E1D42B9DB" # Apple Development: leeborasarang@gmail.com (HLQNBZHQQN) · TEAM 6GPJQ7BQC9
DEVELOPMENT_TEAM="6GPJQ7BQC9"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[build-macos]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

MODE=${1:-debug}
DO_CLEAN=${2:-false}

log "실행 중인 $APP_NAME 종료..."
pkill -x "$APP_NAME" 2>/dev/null || true

if [ "$DO_CLEAN" = true ]; then
  log "clean 수행"
  rm -rf "$BUILD_DIR" ./dist ./out
fi

mkdir -p "$DEST_DIR"

CONFIG_FLAG=""
[ "$MODE" = "release" ] && CONFIG_FLAG="-c release"

log "빌드 시작 (mode: $MODE, version: $VERSION)"
swift build $CONFIG_FLAG

BUILD_MODE_DIR="debug"
[ "$MODE" = "release" ] && BUILD_MODE_DIR="release"
BINARY="$BUILD_DIR/$BUILD_MODE_DIR/$APP_NAME"
APP_BUNDLE="$DEST_DIR/$APP_NAME.app"

if [ ! -f "$BINARY" ]; then
  error "바이너리 없음: $BINARY"
  exit 1
fi

log "앱 번들 생성..."
if [ -z "$APP_BUNDLE" ] || [ "$APP_BUNDLE" != "$DEST_DIR/$APP_NAME.app" ]; then
  error "APP_BUNDLE 경로 이상: '$APP_BUNDLE' (삭제 중단)"
  exit 1
fi
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/"
# ★ Resources/Localizable.xcstrings 는 2026-09-28 에 삭제했다 (왜: TODO 참조).
#   앱은 Sources/RelayConsole/Resources/{en,ko}.lproj/Localizable.strings 만 읽고,
#   이 파일은 612키로 낙오해 있어 **"여기서 고쳐도 아무 일도 안 일어나는" 함정**이 된다.
#   Xcode 워크플로가 필요하면 그때 .lproj 에서 다시 생성할 것.

# SwiftPM resource bundle (Bundle.module — L10n 필수, 없으면 fatalError)
RES_BUNDLE="$BUILD_DIR/$BUILD_MODE_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RES_BUNDLE" ]; then
  rm -rf "$APP_BUNDLE/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"
  cp -R "$RES_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
  log "리소스 번들 복사: ${APP_NAME}_${APP_NAME}.bundle"
else
  error "리소스 번들 없음: $RES_BUNDLE"
  exit 1
fi

# 메뉴바 아이콘 (Off / Online / Template) — Downloads 원본 복사본
for f in Resources/icons/MenuBar*.png; do
  [ -f "$f" ] && cp "$f" "$APP_BUNDLE/Contents/Resources/"
done

# AppIcon.icns 생성 (BrandKit 1024 마스터 — 파생 크기는 여기서 sips 로 만든다)
ICNS_SRC="Resources/icons/AppIcon.icns"
if [ -f "$ICNS_SRC" ]; then
  cp "$ICNS_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
elif [ -f "BrandKit/AppIcons/AppIcon_1024.png" ]; then
  TMP_ICONSET=$(mktemp -d)/AppIcon.iconset
  mkdir -p "$TMP_ICONSET"
  MASTER="BrandKit/AppIcons/AppIcon_1024.png"
  sips -z 16 16     "$MASTER" --out "$TMP_ICONSET/icon_16x16.png"      >/dev/null 2>&1 || true
  sips -z 32 32     "$MASTER" --out "$TMP_ICONSET/icon_16x16@2x.png"   >/dev/null 2>&1 || true
  sips -z 32 32     "$MASTER" --out "$TMP_ICONSET/icon_32x32.png"      >/dev/null 2>&1 || true
  sips -z 64 64     "$MASTER" --out "$TMP_ICONSET/icon_32x32@2x.png"   >/dev/null 2>&1 || true
  sips -z 128 128   "$MASTER" --out "$TMP_ICONSET/icon_128x128.png"    >/dev/null 2>&1 || true
  sips -z 256 256   "$MASTER" --out "$TMP_ICONSET/icon_128x128@2x.png" >/dev/null 2>&1 || true
  sips -z 256 256   "$MASTER" --out "$TMP_ICONSET/icon_256x256.png"    >/dev/null 2>&1 || true
  sips -z 512 512   "$MASTER" --out "$TMP_ICONSET/icon_256x256@2x.png" >/dev/null 2>&1 || true
  sips -z 512 512   "$MASTER" --out "$TMP_ICONSET/icon_512x512.png"    >/dev/null 2>&1 || true
  sips -z 1024 1024 "$MASTER" --out "$TMP_ICONSET/icon_512x512@2x.png" >/dev/null 2>&1 || true
  if iconutil -c icns "$TMP_ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    log "AppIcon.icns 생성 완료"
  else
    warn "iconutil 실패 — 아이콘 생략"
  fi
  rm -rf "$(dirname "$TMP_ICONSET")"
fi

# ── 서명 — Apple Development (비샌드박스 앱 단독 · 2026-10-17 위젯 제거) ─────
log "Apple Development 서명..."
if codesign --force -s "$CODE_SIGN_IDENTITY" \
    --entitlements Entitlements/RelayConsole.entitlements \
    "$APP_BUNDLE" 2>&1 | tail -n 5; then
  log "서명 완료"
else
  error "서명 실패 (중단: 무서명 번들은 실행 시 킬될 수 있음)"
  exit 1
fi

if ! codesign --verify --deep --strict "$APP_BUNDLE" 2>&1; then
  error "서명 검증 실패 (codesign --verify --deep --strict)"
  exit 1
fi
log "서명 검증 통과 (팀 $DEVELOPMENT_TEAM)"

log "완료: $APP_BUNDLE ($BUNDLE_ID, $VERSION)"
open "$APP_BUNDLE" 2>/dev/null || true
