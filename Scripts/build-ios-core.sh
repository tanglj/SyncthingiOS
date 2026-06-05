#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$APP_ROOT/.." && pwd)"
SYNCTHING_ROOT="$WORKSPACE_ROOT/syncthing"

GOBIN="$WORKSPACE_ROOT/.gobin"
GOCACHE="$WORKSPACE_ROOT/.gocache"
GOMODCACHE="$WORKSPACE_ROOT/.gomodcache"
GOMOBILE="$GOBIN/gomobile"
OUT_DIR="$APP_ROOT/SyncthingiOS/Frameworks"

mkdir -p "$GOBIN" "$GOCACHE" "$GOMODCACHE" "$OUT_DIR"
export PATH="$GOBIN:$PATH"

if [[ ! -x "$GOMOBILE" ]]; then
  GOBIN="$GOBIN" GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" \
    go install golang.org/x/mobile/cmd/gomobile@latest
fi

if [[ ! -x "$GOBIN/gobind" ]]; then
  GOBIN="$GOBIN" GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" \
    go install golang.org/x/mobile/cmd/gobind@latest
fi

GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" "$GOMOBILE" init

cd "$SYNCTHING_ROOT"

GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" \
  go generate ./lib/api/auto

GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" "$GOMOBILE" bind \
  -target=ios,iossimulator \
  -o "$OUT_DIR/Ioscore.xcframework" \
  ./mobile/ioscore

echo "Built $OUT_DIR/Ioscore.xcframework"
