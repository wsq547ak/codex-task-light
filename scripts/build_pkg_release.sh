#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
RELEASE_DIR="$REPO_ROOT/release"
STAGING_DIR=$(mktemp -d)
PAYLOAD_ROOT="$STAGING_DIR/payload"
SCRIPTS_DIR="$STAGING_DIR/scripts"
PACKAGE_NAME="codex-task-light-$(date +%Y%m%d-%H%M%S).pkg"
PACKAGE_PATH="$RELEASE_DIR/$PACKAGE_NAME"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$RELEASE_DIR" "$PAYLOAD_ROOT/Applications/codex-task-light/.runtime" "$SCRIPTS_DIR"

"$REPO_ROOT/scripts/build_menubar_app.sh"

rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude '.runtime' \
  --exclude 'release' \
  "$REPO_ROOT/" "$PAYLOAD_ROOT/Applications/codex-task-light/"

rsync -a "$REPO_ROOT/.runtime/CodexTrafficLight.app" "$PAYLOAD_ROOT/Applications/codex-task-light/.runtime/"
cp "$REPO_ROOT/packaging/postinstall" "$SCRIPTS_DIR/postinstall"
chmod +x "$SCRIPTS_DIR/postinstall" "$PAYLOAD_ROOT/Applications/codex-task-light/scripts/install_from_pkg.sh"

pkgbuild \
  --root "$PAYLOAD_ROOT" \
  --identifier "com.scott.codex-task-light" \
  --version "1.0.0" \
  --install-location "/" \
  --scripts "$SCRIPTS_DIR" \
  "$PACKAGE_PATH"

echo "Built pkg at: $PACKAGE_PATH"
