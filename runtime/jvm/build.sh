#!/usr/bin/env bash
# Build kestrel-runtime.jar from Java sources.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUT_DIR="$SCRIPT_DIR/out"
JAR="$SCRIPT_DIR/kestrel-runtime.jar"

# Prefer JAVA_HOME if set and points to Java 21+; otherwise search well-known locations.
_pick_javac() {
  local candidates=(
    "${JAVA_HOME:+$JAVA_HOME/bin/javac}"
    "/usr/lib/jvm/temurin-21-jdk-amd64/bin/javac"
    "/usr/lib/jvm/java-21-openjdk-amd64/bin/javac"
    "javac"
  )
  for c in "${candidates[@]}"; do
    [ -n "$c" ] || continue
    [ -x "$c" ] || command -v "$c" &>/dev/null || continue
    if "$c" -version 2>&1 | grep -qE '(^javac 2[1-9]|version "2[1-9])'; then
      echo "$c"; return
    fi
  done
  echo "javac"
}
JAVAC="$(_pick_javac)"

mkdir -p "$OUT_DIR"
"$JAVAC" -d "$OUT_DIR" --release 21 \
  "$SRC_DIR/kestrel/runtime/KUnit.java" \
  "$SRC_DIR/kestrel/runtime/KFunction.java" \
  "$SRC_DIR/kestrel/runtime/KFunctionRef.java" \
  "$SRC_DIR/kestrel/runtime/KRecord.java" \
  "$SRC_DIR/kestrel/runtime/KAdt.java" \
  "$SRC_DIR/kestrel/runtime/KException.java" \
  "$SRC_DIR/kestrel/runtime/KArray.java" \
  "$SRC_DIR/kestrel/runtime/KList.java" \
  "$SRC_DIR/kestrel/runtime/KNil.java" \
  "$SRC_DIR/kestrel/runtime/KCons.java" \
  "$SRC_DIR/kestrel/runtime/KOption.java" \
  "$SRC_DIR/kestrel/runtime/KNone.java" \
  "$SRC_DIR/kestrel/runtime/KSome.java" \
  "$SRC_DIR/kestrel/runtime/KTask.java" \
  "$SRC_DIR/kestrel/runtime/KResult.java" \
  "$SRC_DIR/kestrel/runtime/KErr.java" \
  "$SRC_DIR/kestrel/runtime/KOk.java" \
  "$SRC_DIR/kestrel/runtime/KMath.java" \
  "$SRC_DIR/kestrel/runtime/KRuntime.java"
cd "$OUT_DIR"
jar cf "$JAR" kestrel/
echo "Built $JAR"
