#!/bin/bash
# v1.0 디스패처 — 실제 빌드는 scripts/build-{platform}.sh
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[build_and_run]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

MODE="debug"
PLATFORM="auto"
DO_CLEAN=false

for arg in "$@"; do
  case $arg in
    debug|release) MODE="$arg" ;;
    macos|ios|android|web|all) PLATFORM="$arg" ;;
    clean) DO_CLEAN=true ;;
    test)
      log "테스트 실행 (unit)"
      swift test
      exit 0
      ;;
    -h|--help) echo "Usage: ./build_and_run.sh [debug|release] [macos] [clean] [test]"; exit 0 ;;
    *) echo "알 수 없는 인자: $arg"; exit 1 ;;
  esac
done

[ "$PLATFORM" = "auto" ] && PLATFORM="macos"

case $PLATFORM in
  macos|all) exec ./scripts/build-macos.sh "$MODE" "$DO_CLEAN" ;;
  *) error "$PLATFORM: 지원하지 않는 플랫폼 (현재 macOS 전용)"; exit 1 ;;
esac
