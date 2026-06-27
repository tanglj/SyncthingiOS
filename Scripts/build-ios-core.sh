#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SYNCTHING_ROOT="$APP_ROOT/ThirdParty"

GOBIN="$APP_ROOT/.gobin"
GOCACHE="$APP_ROOT/.gocache"
GOMODCACHE="$APP_ROOT/.gomodcache"
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

CORE_VERSION="${VERSION:-}"
if [[ -z "$CORE_VERSION" ]]; then
  if [[ -f RELEASE ]]; then
    CORE_VERSION="$(tr -d '[:space:]' < RELEASE)"
  else
    CORE_VERSION="$(git describe --always --dirty --abbrev=8 2>/dev/null || true)"
  fi
fi
if [[ -z "$CORE_VERSION" || "$CORE_VERSION" == "unknown-dev" || ! "$CORE_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  CORE_VERSION="v0.0.0-ios"
fi

GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" \
  go generate ./lib/api/auto

GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" "$GOMOBILE" bind \
  -target=ios,iossimulator \
  -ldflags="-w -buildid= -X github.com/syncthing/syncthing/lib/build.Version=$CORE_VERSION -X github.com/syncthing/syncthing/lib/build.Tags=ios" \
  -o "$OUT_DIR/Ioscore.xcframework" \
  ./mobile/ioscore

echo "Built $OUT_DIR/Ioscore.xcframework ($CORE_VERSION)"
