#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"

COMPILER_DIR="$ROOT/compiler"
COMPILER_CLI="$COMPILER_DIR/dist/cli.js"
ENTRY="$ROOT/stdlib/kestrel/tools/compiler/cli-entry.ks"
BOOTSTRAP_ROOT="${KESTREL_BOOTSTRAP_ROOT:-$HOME/.kestrel/bootstrap}"
OUT_DIR="$BOOTSTRAP_ROOT/compiler"
CLASSES_DIR="$OUT_DIR/classes"
JAR_PATH="$OUT_DIR/compiler-bootstrap.jar"

usage() {
  echo "Usage: ./scripts/build-bootstrap-jar.sh" >&2
}

hash_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    shasum -a 256 "$f" | awk '{print $1}'
  fi
}

require_tools() {
  command -v node >/dev/null 2>&1 || { echo "build-bootstrap-jar: node not found" >&2; exit 1; }
  command -v java >/dev/null 2>&1 || { echo "build-bootstrap-jar: java not found" >&2; exit 1; }
  command -v javac >/dev/null 2>&1 || { echo "build-bootstrap-jar: javac not found" >&2; exit 1; }
  command -v jar >/dev/null 2>&1 || { echo "build-bootstrap-jar: jar not found" >&2; exit 1; }
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

require_tools

if [ ! -f "$ENTRY" ]; then
  echo "build-bootstrap-jar: missing entry source: $ENTRY" >&2
  exit 1
fi

echo "[bootstrap-jar] wiping ~/.kestrel"
rm -rf "$HOME/.kestrel"

mkdir -p "$OUT_DIR"
rm -rf "$CLASSES_DIR"
mkdir -p "$CLASSES_DIR"

echo "[bootstrap-jar] building TypeScript compiler"
(cd "$COMPILER_DIR" && npm run build >/dev/null)

echo "[bootstrap-jar] compiling executable compiler entrypoint"
node "$COMPILER_CLI" "$ENTRY" --target jvm -o "$CLASSES_DIR"

echo "[bootstrap-jar] packaging JAR"
rm -f "$JAR_PATH"
(
  cd "$CLASSES_DIR"
  jar --create --file "$JAR_PATH" .
)

# Verify required entry classes are present.
if ! jar tf "$JAR_PATH" | grep -q 'Cli_entry.class'; then
  echo "build-bootstrap-jar: Cli_entry.class missing from bootstrap JAR" >&2
  exit 1
fi
if ! jar tf "$JAR_PATH" | grep -q 'Cli_main.class'; then
  echo "build-bootstrap-jar: Cli_main.class missing from bootstrap JAR" >&2
  exit 1
fi

# Install JAR to Maven cache layout: ~/.kestrel/maven/lang/kestrel/compile/1.0/compile-1.0.jar
MAVEN_ROOT="${KESTREL_MAVEN_CACHE:-$HOME/.kestrel/maven}"
MAVEN_GROUP_PATH="$MAVEN_ROOT/lang/kestrel"
MAVEN_ARTIFACT_DIR="$MAVEN_GROUP_PATH/compile/1.0"
MAVEN_JAR_PATH="$MAVEN_ARTIFACT_DIR/compile-1.0.jar"
MAVEN_SHA1_PATH="$MAVEN_JAR_PATH.sha1"

echo "[bootstrap-jar] installing to Maven cache"
mkdir -p "$MAVEN_ARTIFACT_DIR"
cp "$JAR_PATH" "$MAVEN_JAR_PATH"

# Compute and write SHA1 sidecar
MAVEN_JAR_SHA1=$(hash_file "$MAVEN_JAR_PATH")
echo "$MAVEN_JAR_SHA1  compile-1.0.jar" > "$MAVEN_SHA1_PATH"

rev="unknown"
if git -C "$ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
  rev=$(git -C "$ROOT" rev-parse HEAD)
fi

# Clean up intermediate bootstrap build directory; everything useful is in Maven cache.
rm -rf "$BOOTSTRAP_ROOT"

echo "[bootstrap-jar] PASS"
echo "  maven jar : $MAVEN_JAR_PATH"
echo "  maven sha1: $MAVEN_SHA1_PATH"
