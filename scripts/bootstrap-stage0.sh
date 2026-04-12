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
RUNTIME_JAR="$ROOT/runtime/jvm/kestrel-runtime.jar"
JVM_CACHE="${KESTREL_JVM_CACHE:-$HOME/.kestrel/jvm}"
SELFHOST_ENTRY="$ROOT/stdlib/kestrel/tools/compiler/cli-main.ks"
SAMPLE="${1:-$ROOT/samples/mandelbrot.ks}"
WORK_ROOT="$ROOT/.kestrel/bootstrap-stage0"
TS_OUT="$WORK_ROOT/ts"
STAGE0_OUT="$WORK_ROOT/stage0"

usage() {
  echo "Usage: ./scripts/bootstrap-stage0.sh [sample.ks]" >&2
}

ensure_tools() {
  command -v node >/dev/null 2>&1 || { echo "bootstrap-stage0: node not found" >&2; exit 1; }
  command -v java >/dev/null 2>&1 || { echo "bootstrap-stage0: java not found" >&2; exit 1; }
  command -v javac >/dev/null 2>&1 || { echo "bootstrap-stage0: javac not found" >&2; exit 1; }
}

main_class_for() {
  local abs_ks rel dir base first rest internal
  abs_ks=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  rel="${abs_ks#/}"
  dir=$(dirname "$rel")
  base=$(basename "$rel" .ks)
  base=$(echo "$base" | sed 's/[^a-zA-Z0-9_]/_/g')
  first=$(echo "$base" | cut -c1 | tr 'a-z' 'A-Z')
  rest=$(echo "$base" | cut -c2-)
  if [ "$dir" = "." ]; then
    internal="${first}${rest}"
  else
    internal="$(echo "$dir" | sed 's/[^a-zA-Z0-9_/]/_/g' | tr '/' '.').${first}${rest}"
  fi
  echo "$internal"
}

run_java_main() {
  local class_dir="$1"
  local main_class="$2"
  shift 2
  java -cp "$RUNTIME_JAR:$class_dir" "$main_class" "$@"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [ ! -f "$SAMPLE" ]; then
  echo "bootstrap-stage0: sample not found: $SAMPLE" >&2
  exit 1
fi

ensure_tools

mkdir -p "$WORK_ROOT"
rm -rf "$TS_OUT" "$STAGE0_OUT"
mkdir -p "$TS_OUT" "$STAGE0_OUT"

echo "[stage0] building bootstrap TypeScript compiler and JVM runtime"
(cd "$COMPILER_DIR" && npm run build >/dev/null)
(cd "$ROOT/runtime/jvm" && bash build.sh >/dev/null)

echo "[stage0] compiling self-hosted CLI entrypoint to stage-0 classes"
node "$COMPILER_CLI" "$SELFHOST_ENTRY" --target jvm -o "$STAGE0_OUT"

echo "[stage0] compiling baseline sample with TypeScript compiler"
node "$COMPILER_CLI" "$SAMPLE" --target jvm -o "$TS_OUT"

SAMPLE_MAIN=$(main_class_for "$SAMPLE")
CLI_MAIN=$(main_class_for "$SELFHOST_ENTRY")

echo "[stage0] executing baseline sample"
run_java_main "$TS_OUT" "$SAMPLE_MAIN" > "$WORK_ROOT/ts.stdout"

echo "[stage0] executing stage-0 compiler binary (build command smoke)"
run_java_main "$STAGE0_OUT" "$CLI_MAIN" build

echo "[stage0] compiling sample through canonical build path for semantic comparison"
"$ROOT/kestrel" build "$SAMPLE"

echo "[stage0] executing sample after stage-0 compile flow"
run_java_main "$JVM_CACHE" "$SAMPLE_MAIN" > "$WORK_ROOT/stage0.stdout"

if diff -u "$WORK_ROOT/ts.stdout" "$WORK_ROOT/stage0.stdout" >/dev/null; then
  echo "[stage0] PASS: semantic output matches baseline"
else
  echo "[stage0] FAIL: semantic output mismatch" >&2
  diff -u "$WORK_ROOT/ts.stdout" "$WORK_ROOT/stage0.stdout" || true
  exit 1
fi

echo "[stage0] artifacts:"
echo "  baseline classes: $TS_OUT"
echo "  stage-0 classes:  $STAGE0_OUT"
echo "  baseline output:  $WORK_ROOT/ts.stdout"
echo "  stage-0 output:   $WORK_ROOT/stage0.stdout"
