# gawk-static

Portable builds of [GNU Awk](https://www.gnu.org/software/gawk/), built with
[zig](https://ziglang.org) as the C toolchain.

- Linux glibc: only glibc is linked dynamically, and only symbols up to glibc 2.17, so the
  binaries run on anything from CentOS 7 onwards
- Linux musl (`--static`): fully static, no runtime dependencies at all (e.g. Alpine)
- macOS: only libSystem is dynamic (it ships with macOS, which has no fully static binaries)

gawk is built without readline (so the debugger `-D` has no line editing), without MPFR (so
`-M` for arbitrary precision is unavailable), without dynamic extensions (`@load`), without the
persistent memory allocator (`--persist`), and without translated messages.

## Prerequisites

- `zig`, GNU make (the `make` 3.81 of macOS is enough), `git`
- On macOS: Xcode Command Line Tools (SDK)

## Installation

Clone the repo with submodules (shallow, the history of gawk is not needed):

```shell
git clone --recurse-submodules --shallow-submodules https://github.com/audivir/gawk-static
cd gawk-static
```

## Usage

```shell
./build.sh
```

This builds gawk from `vendor/gawk`. Output is installed under `dist/`:

- `dist/bin/gawk`: the binary; copy it anywhere on your `PATH`
- `dist/share/man/man1/gawk.1`: the man page

Pass `--static` for the fully static musl build on Linux (output in `dist-static/`), `--clean` to
remove previous build output first, and `--jobs N` to control parallelism.

To run the smoke tests against the build:

```shell
./tests/run_smoke_tests.sh            # dist/
./tests/run_smoke_tests.sh --static   # dist-static/
```

## Releases

Publishing a GitHub release tagged with the gawk version (e.g. `v5.4.1`, matching the tag checked
out in `vendor/gawk`) builds and attaches `gawk-static-<platform>.tar.gz` for `macos-arm64`,
`linux-amd64`, `linux-arm64`, `linux-musl-amd64`, and `linux-musl-arm64`, together with the
sources they were built from (`gawk-static-sources.tar.gz`).

To update gawk, check out a new release tag in its submodule and commit it, e.g.
`git -C vendor/gawk fetch --depth 1 origin tag gawk-5.4.2 && git -C vendor/gawk checkout gawk-5.4.2`.

## Acknowledgments

This repository builds and vendors [GNU Awk](https://www.gnu.org/software/gawk/) by the Free
Software Foundation, Arnold D. Robbins, and contributors, unmodified, as a git submodule under
`vendor/`.

## License

MIT for the code in this repository. See `NOTICE` for the license of gawk and the resulting
binaries, which are GPL-3.0-or-later.
