#!/usr/bin/env bash
# A calibre-server for CalibreServerContractTests. The library holds one EPUB and is named with
# a space and non-ASCII characters (its key is "Test_Library_测试"). It has two users:
# contract-writer and the read-only contract-reader. Authentication is calibre's default
# (Digest over HTTP).
#
#   calibre-contract-server.sh start DIR   seed DIR if it's new, start the server, wait for it
#   calibre-contract-server.sh stop DIR    stop the server started on DIR
#
# start prints the TEST_RUNNER_ variables the tests read, and on GitHub Actions also adds them
# to $GITHUB_ENV. CALIBRE_BIN is the directory of calibre's command-line tools, CALIBRE_PORT
# the port (18080).
set -euo pipefail

BIN=${CALIBRE_BIN:-/Applications/calibre.app/Contents/MacOS}
PORT=${CALIBRE_PORT:-18080}
WRITER=contract-writer
WRITER_PASSWORD=writer-pass
READER=contract-reader
READER_PASSWORD=reader-pass

seed() {
  local dir=$1 library=$2
  printf 'Contract Test Book\n\nChapter One\n\nIt was a bright cold day in April.\n\nChapter Two\n\nThe second chapter.\n' > "$dir/book.txt"
  "$BIN/ebook-convert" "$dir/book.txt" "$dir/book.epub" --title "Contract Test Book" --authors "Test Author" > "$dir/convert.log"
  mkdir -p "$library"
  "$BIN/calibredb" add --with-library "$library" "$dir/book.epub"
  "$BIN/calibre-server" --userdb "$dir/users.sqlite" --manage-users -- add "$WRITER" "$WRITER_PASSWORD"
  "$BIN/calibre-server" --userdb "$dir/users.sqlite" --manage-users -- add "$READER" "$READER_PASSWORD"
  "$BIN/calibre-server" --userdb "$dir/users.sqlite" --manage-users -- readonly "$READER" set
}

start() {
  local dir=$1 library="$1/Test Library 测试" url="http://127.0.0.1:$PORT" ready=0
  mkdir -p "$dir"
  [ -f "$library/metadata.db" ] || seed "$dir" "$library"

  nohup "$BIN/calibre-server" --port "$PORT" --listen-on 127.0.0.1 \
    --enable-auth --userdb "$dir/users.sqlite" \
    --pidfile "$dir/server.pid" --log "$dir/server.log" --access-log "$dir/access.log" \
    "$library" > "$dir/server.out" 2>&1 &

  for _ in $(seq 1 60); do
    if curl -sf -o /dev/null --digest -u "$WRITER:$WRITER_PASSWORD" "$url/ajax/library-info"; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "$ready" -ne 1 ]; then
    echo "calibre-server didn't answer on $url" >&2
    cat "$dir/server.out" "$dir/server.log" >&2 2>/dev/null || true
    exit 1
  fi

  local variables="TEST_RUNNER_YABR_CALIBRE_URL=$url
TEST_RUNNER_YABR_CALIBRE_USER=$WRITER
TEST_RUNNER_YABR_CALIBRE_PASSWORD=$WRITER_PASSWORD"
  echo "$variables"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "$variables" >> "$GITHUB_ENV"
  fi
}

# Waits for the server to exit: until then it holds the library, and a new server on it would
# wait for the lock.
stop() {
  local pidfile="$1/server.pid" pid
  [ -f "$pidfile" ] || return 0
  pid=$(cat "$pidfile")
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 30); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$pidfile"
}

case ${1:-} in
  start | stop)
    [ -n "${2:-}" ] || { echo "usage: $0 start|stop DIR" >&2; exit 2; }
    "$1" "$2"
    ;;
  *)
    echo "usage: $0 start|stop DIR" >&2
    exit 2
    ;;
esac
