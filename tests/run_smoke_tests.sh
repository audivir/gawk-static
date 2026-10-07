#!/usr/bin/env bash
# Usage: ./tests/run_smoke_tests.sh [--static] [--dist DIR]
# shellcheck disable=SC2016 # $ in the awk programs is expanded by gawk, not the shell.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT_DIR/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --static)
      DIST="$ROOT_DIR/dist-static"
      shift
      ;;
    --dist)
      DIST="$(cd "$2" && pwd)"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GAWK="$DIST/bin/gawk"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "ok: $*"; }
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
# runs gawk with the remaining arguments and compares its output with the first argument.
expect() {
  local want="$1" got
  shift
  got="$("$GAWK" "$@")" || fail "gawk $* exited with $?"
  [ "$got" = "$want" ] || fail "gawk $*: got '$got', want '$want'"
}

version="$("$GAWK" --version | head -n 1)"
echo "$version" | grep -q '^GNU Awk ' || fail "gawk --version"
pass "$version"

expect 3 'BEGIN { print 1 + 2 }'
expect "b-a" 'BEGIN { print gensub(/(a)(b)/, "\\2-\\1", "g", "ab") }'
expect "1 2 3" 'BEGIN { n = split("3 1 2", a); asort(a); print a[1], a[2], a[3] }'
expect "x=7" -v x=7 'BEGIN { print "x=" x }'
printf 'a,b\nc,d\n' >"$TMP/in.csv"
expect "b d" -F, '{ s = s (NR > 1 ? " " : "") $2 } END { print s }' "$TMP/in.csv"
expect "$TMP/in.csv" 'BEGINFILE { print FILENAME; nextfile }' "$TMP/in.csv"
pass "arithmetic, gensub, asort, -v, -F, BEGINFILE"

expect "hello" 'BEGIN { "echo hello" | getline line; print line }'
expect "2" 'BEGIN { print "b\na" | "sort | wc -l | tr -d \" \""; close("sort | wc -l | tr -d \" \"") }'
expect "1970" 'BEGIN { print strftime("%Y", 0, 1) }'
pass "pipes, getline, strftime"

# a Linux binary without versioned glibc symbols is the static musl build.
LIBC=
if [ "$(uname -s)" = Linux ]; then
  LIBC=musl
  LC_ALL=C grep -a -q 'GLIBC_2\.' "$GAWK" && LIBC=glibc
fi

# multibyte characters count as one in a UTF-8 locale. musl accepts any locale name as UTF-8,
# while glibc silently falls back to bytes if the locale is not installed.
if [ "$LIBC" = musl ]; then
  utf8=C.UTF-8
elif [ "$(uname -s)" = Darwin ]; then
  utf8=en_US.UTF-8
else
  utf8="$(locale -a 2>/dev/null | grep -i -m 1 -E '^(C|en_US)\.utf-?8$' || true)"
fi
if [ -n "$utf8" ]; then
  got="$(LC_ALL="$utf8" "$GAWK" 'BEGIN { print length("äöü") }')"
  [ "$got" = 3 ] || fail "multibyte length in $utf8: got $got, want 3"
  pass "multibyte characters ($utf8)"
fi

if [ "$LIBC" = glibc ]; then
  max="$(LC_ALL=C grep -aoh 'GLIBC_2\.[0-9]*' "$GAWK" | sort -uV | tail -n 1)"
  [ "$(printf '%s\n' "$max" GLIBC_2.17 | sort -V | tail -n 1)" = GLIBC_2.17 ] \
    || fail "needs $max, newer than GLIBC_2.17"
  pass "glibc floor ($max)"
fi

echo "all smoke tests passed"
