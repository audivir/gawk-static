#!/usr/bin/env bash
# Usage: ./build.sh [--jobs N] [--clean] [--static]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
CLEAN=0
STATIC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --static)
      STATIC=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GLIBC_VER=2.17

OS="$(uname -s)"
ARCH="$(uname -m)"
[ "$ARCH" = arm64 ] && ARCH=aarch64

SUFFIX=""
[ "$STATIC" = 1 ] && SUFFIX="-static"
WORK="$ROOT_DIR/build$SUFFIX"
DIST="$ROOT_DIR/dist$SUFFIX"

case "$OS-$ARCH" in
  Linux-x86_64 | Linux-aarch64)
    ZIG_TARGET=$ARCH-linux-gnu.$GLIBC_VER
    [ "$STATIC" = 1 ] && ZIG_TARGET=$ARCH-linux-musl
    ;;
  Darwin-aarch64 | Darwin-x86_64)
    ZIG_TARGET=native
    ;;
  *)
    echo "unsupported host $OS-$ARCH" >&2
    exit 1
    ;;
esac
if [ "$OS" != Linux ] && [ "$STATIC" = 1 ]; then
  echo "--static is only supported on Linux" >&2
  exit 1
fi

MAKE="${MAKE:-$(command -v gmake || command -v make)}"
"$MAKE" --version 2>/dev/null | grep -q 'GNU Make' || {
  echo "GNU make required" >&2
  exit 1
}

if [ "$ZIG_TARGET" = native ]; then export CC="zig cc"; else export CC="zig cc -target $ZIG_TARGET"; fi
# zig ar lacks the u flag of the default ARFLAGS.
export AR="zig ar" ARFLAGS=cr
export RANLIB="zig ranlib"

if [ "$CLEAN" = 1 ]; then
  echo ">>> cleaning $WORK and $DIST"
  rm -rf "$WORK" "$DIST"
fi
mkdir -p "$WORK"

if [ ! -f "$ROOT_DIR/vendor/gawk/.git" ] && [ ! -d "$ROOT_DIR/vendor/gawk/.git" ]; then
  echo "vendor/gawk is missing, run: git submodule update --init --depth 1" >&2
  exit 1
fi
if [ ! -d "$WORK/gawk" ]; then
  echo ">>> preparing gawk ($(git -C "$ROOT_DIR/vendor/gawk" describe --tags 2>/dev/null || echo unknown))"
  cp -R "$ROOT_DIR/vendor/gawk" "$WORK/gawk"
  rm -rf "$WORK/gawk/.git"
  # the copy has fresh timestamps, so restore the order of the generated files, or make would
  # regenerate them with autotools.
  (cd "$WORK/gawk" && sh ./bootstrap.sh)
fi

echo ">>> gawk"
(
  cd "$WORK/gawk"
  [ -f Makefile ] && "$MAKE" distclean >/dev/null 2>&1 || true
  LDFLAGS="-s"
  [ "$STATIC" = 1 ] && LDFLAGS="-static $LDFLAGS"
  # dynamic extensions and the persistent memory allocator need a dynamic binary, readline and
  # MPFR would be dynamic dependencies, and the message catalogs are not installed.
  ./configure \
    --prefix=/usr/local \
    --disable-extensions --disable-pma --disable-nls --disable-dependency-tracking \
    --without-readline --without-mpfr \
    LDFLAGS="$LDFLAGS"
  # builds only the binary, skipping the extensions, the awklib helpers, and the docs.
  "$MAKE" -j"$JOBS" -C support
  "$MAKE" -j"$JOBS" gawk
  rm -rf "$DIST"
  mkdir -p "$DIST/bin" "$DIST/share/man/man1"
  cp gawk "$DIST/bin/gawk"
  cp doc/gawk.1 "$DIST/share/man/man1/gawk.1"
)

GAWK_BIN="$DIST/bin/gawk"
echo
echo ">>> done: $GAWK_BIN"
"$GAWK_BIN" --version | head -n 1
if [ "$OS" = Linux ]; then
  if [ "$STATIC" = 1 ]; then
    # static musl libc embeds the loader path as a string, so check for an interpreter header.
    if readelf -l "$GAWK_BIN" | grep -q INTERP; then
      echo "WARNING: gawk references a dynamic loader, not fully static" >&2
    else
      echo "fully static"
    fi
  elif LC_ALL=C grep -a -q -E 'lib(readline|mpfr|gmp|sigsegv)[a-z]*\.so' "$GAWK_BIN"; then
    echo "WARNING: gawk links a dependency dynamically, not only glibc" >&2
  else
    echo "only glibc is dynamic"
  fi
else
  otool -L "$GAWK_BIN"
fi
