#!/usr/bin/env bash

set -euo pipefail

THIS_DIR=$(cd "$(dirname "$0")"; pwd -P)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/firtool-resolver-url.XXXXXX")
SERVER_PID=

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

unset CHISEL_FIRTOOL_PATH

VERSION="firtool-1.162.0-param-url-test"
export CHISEL_FIRTOOL_CACHE="$TEST_DIR/cache"

python3 "$THIS_DIR/url_server.py" "$THIS_DIR/url_firtool" > "$TEST_DIR/port" 2> "$TEST_DIR/server.log" &
SERVER_PID=$!

for _ in $(seq 1 100); do
  if [[ -s "$TEST_DIR/port" ]]; then
    break
  fi
  sleep 0.05
done
if [[ ! -s "$TEST_DIR/port" ]]; then
  cat "$TEST_DIR/server.log"
  exit 1
fi

PORT=$(head -n 1 "$TEST_DIR/port")
SPEC="$VERSION@http://127.0.0.1:$PORT/download"

resolve() {
  cs launch --scala "$SCALA_VERSION" \
    "org.chipsalliance::firtool-resolver:$FIRTOOL_RESOLVER_VERSION" \
    --main firtoolresolver.Main \
    -- \
    -v \
    "$1"
}

FIRST=$(resolve "$SPEC")
# CHECK: Using explicitly requested firtool URL: http://127.0.0.1:
# CHECK: Downloading firtool from http://127.0.0.1:
# CHECK: Atomically moving
case "$FIRST" in
  "$CHISEL_FIRTOOL_CACHE"/*) ;;
  *)
    echo "CHISEL_FIRTOOL_CACHE was not used: $FIRST"
    exit 1
    ;;
esac
"$FIRST" --version
# CHECK: CIRCT firtool-1.162.0-param-url-test

HTTP_FAILURE_CACHE="$TEST_DIR/http-failure-cache"
if CHISEL_FIRTOOL_CACHE="$HTTP_FAILURE_CACHE" resolve "$VERSION@http://127.0.0.1:$PORT/missing"; then
  echo "HTTP failure unexpectedly succeeded"
  exit 1
fi
# CHECK: Unable to download firtool from http://127.0.0.1:
# CHECK: HTTP 404
if [[ -e "$HTTP_FAILURE_CACHE" ]]; then
  echo "HTTP failure created a cache directory"
  exit 1
fi

kill "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=

SECOND=$(resolve "$SPEC")
# CHECK: Firtool binary for http://127.0.0.1:
# CHECK: already exists at
if [[ "$FIRST" != "$SECOND" ]]; then
  echo "cache returned a different firtool path: $FIRST != $SECOND"
  exit 1
fi

OVERRIDE_CACHE="$TEST_DIR/override-cache"
OVERRIDDEN=$(
  CHISEL_FIRTOOL_CACHE="$OVERRIDE_CACHE" \
  CHISEL_FIRTOOL_PATH="$(dirname "$FIRST")" \
  resolve "$SPEC"
)
# CHECK: Running: {{.+}}bin{{.}}firtool --version
if [[ "$OVERRIDDEN" != "$FIRST" ]]; then
  echo "CHISEL_FIRTOOL_PATH was not preferred: $OVERRIDDEN != $FIRST"
  exit 1
fi
if [[ -e "$OVERRIDE_CACHE/$VERSION/bin/firtool" ]]; then
  echo "URL was downloaded despite CHISEL_FIRTOOL_PATH"
  exit 1
fi

FAILURE_CACHE="$TEST_DIR/failure-cache"
if CHISEL_FIRTOOL_CACHE="$FAILURE_CACHE" resolve "${VERSION}@not-a-url"; then
  echo "invalid URL unexpectedly succeeded"
  exit 1
fi
# CHECK: Invalid firtool URL in version@URL source: not-a-url
if [[ -e "$FAILURE_CACHE" ]]; then
  echo "invalid URL created a cache directory"
  exit 1
fi
