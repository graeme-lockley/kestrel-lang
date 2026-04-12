#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"

COMPILER_CLI="$ROOT/compiler/dist/cli.js"
RUNTIME_JAR="$ROOT/runtime/jvm/kestrel-runtime.jar"
JVM_CACHE="${KESTREL_JVM_CACHE:-$HOME/.kestrel/jvm}"
SELFHOST_ENTRY="$ROOT/stdlib/kestrel/tools/compiler/cli-main.ks"
SAMPLE="${1:-$ROOT/samples/mandelbrot.ks}"
WORK_ROOT="$ROOT/.kestrel/bootstrap-stage1"
STAGE1_OUT="$WORK_ROOT/stage1"

usage() {
  echo "Usage: ./scripts/bootstrap-stage1.sh [sample.ks]" >&2
}

ensure_tools() {
  command -v node >/dev/null 2>&1 || { echo "bootstrap-stage1: node not found" >&2; exit 1; }
  command -v java >/dev/null 2>&1 || { echo "bootstrap-stage1: java not found" >&2; exit 1; }
  command -v javac >/dev/null 2>&1 || { echo "bootstrap-stage1: javac not found" >&2; exit 1; }
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
  echo "bootstrap-stage1: sample not found: $SAMPLE" >&2
  exit 1
fi

ensure_tools

mkdir -p "$WORK_ROOT"
rm -rf "$STAGE1_OUT"
mkdir -p "$STAGE1_OUT"

echo "[stage1] preparing stage-0 baseline"
"$ROOT/scripts/bootstrap-stage0.sh" "$SAMPLE"

echo "[stage1] generating stage-1 candidate artifact"
# Current transition topology still uses TypeScript bootstrap as the canonical
# compile path. Stage-1 generation is therefore provisional until self-hosted
# argument forwarding and compile delegation are fully removed.
node "$COMPILER_CLI" "$SELFHOST_ENTRY" --target jvm -o "$STAGE1_OUT"

CLI_MAIN=$(main_class_for "$SELFHOST_ENTRY")
SAMPLE_MAIN=$(main_class_for "$SAMPLE")

echo "[stage1] executing stage-1 compiler binary (build command smoke)"
run_java_main "$STAGE1_OUT" "$CLI_MAIN" build

echo "[stage1] compiling sample through canonical build path for parity"
"$ROOT/kestrel" build "$SAMPLE"

echo "[stage1] running stage-0 and stage-1 parity samples"
cp "$ROOT/.kestrel/bootstrap-stage0/stage0.stdout" "$WORK_ROOT/stage0.stdout"
run_java_main "$JVM_CACHE" "$SAMPLE_MAIN" > "$WORK_ROOT/stage1.stdout"

if diff -u "$WORK_ROOT/stage0.stdout" "$WORK_ROOT/stage1.stdout" >/dev/null; then
  echo "[stage1] PASS: semantic output matches stage-0 baseline"
else
  echo "[stage1] FAIL: semantic output mismatch vs stage-0 baseline" >&2
  diff -u "$WORK_ROOT/stage0.stdout" "$WORK_ROOT/stage1.stdout" || true
  exit 1
fi

echo "[stage1] NOTE: fallback topology remains active; Node/TypeScript are still required in the default build path."
echo "[stage1] artifacts:"
echo "  stage-1 classes: $STAGE1_OUT"
echo "  stage-0 output:  $WORK_ROOT/stage0.stdout"
echo "  stage-1 output:  $WORK_ROOT/stage1.stdout"
