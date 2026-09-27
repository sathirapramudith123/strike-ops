#!/usr/bin/env bash
# Builds the Opus voice codec GDExtension (native/opus_voice) into
# addons/opus_voice/bin/.
#
#   tools/build_opus.sh                  # linux + windows + macos (what this machine can build)
#   tools/build_opus.sh linux            # libopus_voice.linux.x86_64.so     (glibc 2.28+)
#   tools/build_opus.sh windows          # libopus_voice.windows.x86_64.dll
#   tools/build_opus.sh macos            # libopus_voice.macos.{arm64,x86_64}.dylib
#
# Needs CMake 3.17+ and internet (downloads godot-cpp 4.4 + libopus 1.5.2).
# Compilers, per target:
#   linux   — Zig (portable: `pip install ziglang` or zig in PATH); falls back to gcc/clang
#             (then the library only runs on distros with the same or newer glibc)
#   windows — MinGW-w64 on Linux (`apt install mingw-w64`), or MSVC / MinGW on Windows
#   macos   — Xcode clang on a Mac, or Zig from Linux
#
# Afterwards run `godot --headless --path . --import` (or open the editor) once
# so Godot registers the extension.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=native/opus_voice
BUILD=${OPUS_BUILD_DIR:-$ROOT/native/build}
JOBS=$( (nproc || sysctl -n hw.ncpu) 2>/dev/null || echo 4)
HOST=$(uname -s)

# Zig command: zig in PATH or the pip package.
zig_cmd() {
  if command -v zig >/dev/null 2>&1; then echo "zig"; return 0; fi
  for py in "${ZIG_PYTHON:-}" python3 python; do
    [ -n "$py" ] && "$py" -c "import ziglang" 2>/dev/null && { echo "$(command -v "$py") -m ziglang"; return 0; }
  done
  return 1
}

# Compiler wrappers for one Zig target (drops -Wl,-v, which Zig's Mach-O linker rejects).
zig_wrappers() {
  local target=$1 dir=$2 zig
  zig=$(zig_cmd)
  mkdir -p "$dir"
  for lang in cc c++; do
    cat > "$dir/$lang" <<EOS
#!/bin/sh
for a; do shift; [ "\$a" = "-Wl,-v" ] || set -- "\$@" "\$a"; done
exec $zig $lang -target $target "\$@"
EOS
    chmod +x "$dir/$lang"
  done
  # Archives must be in a format Zig's linkers read (BSD-style for Mach-O).
  for tool in ar ranlib; do
    printf '#!/bin/sh\nexec %s %s "$@"\n' "$zig" "$tool" > "$dir/$tool"
    chmod +x "$dir/$tool"
  done
}

# CMake flags to use the wrappers in $1.
zig_flags() {
  echo "-DCMAKE_C_COMPILER=$1/cc -DCMAKE_CXX_COMPILER=$1/c++ -DCMAKE_AR=$1/ar -DCMAKE_RANLIB=$1/ranlib -DOV_ZIG=ON"
}

configure_and_build() {
  local dir=$1; shift
  cmake -S "$SRC" -B "$dir" -DCMAKE_BUILD_TYPE=Release "$@" > "$dir.log" 2>&1 \
    || { tail -30 "$dir.log"; exit 1; }
  cmake --build "$dir" --config Release -j "$JOBS" >> "$dir.log" 2>&1 \
    || { grep -E "error" "$dir.log" | head -20; exit 1; }
}

build_linux() {
  echo "-- linux x86_64"
  if zig_cmd >/dev/null; then
    zig_wrappers x86_64-linux-gnu.2.28 "$BUILD/zig-linux"
    # shellcheck disable=SC2046
    configure_and_build "$BUILD/linux" $(zig_flags "$BUILD/zig-linux")
  else
    echo "   (no Zig — building with the system compiler; needs this glibc or newer)"
    configure_and_build "$BUILD/linux"
  fi
}

build_windows() {
  echo "-- windows x86_64"
  if [ "$HOST" = Linux ] || [ "$HOST" = Darwin ]; then
    command -v x86_64-w64-mingw32-g++-posix >/dev/null \
      || { echo "   needs MinGW-w64: apt install mingw-w64"; return 1; }
    configure_and_build "$BUILD/windows" -DCMAKE_TOOLCHAIN_FILE="$ROOT/$SRC/cmake/mingw-w64-x86_64.cmake"
  else
    configure_and_build "$BUILD/windows"
  fi
}

build_macos() {
  for arch in arm64 x86_64; do
    echo "-- macos $arch"
    local neon=()
    [ "$arch" = arm64 ] && neon=(-DOPUS_MAY_HAVE_NEON=ON -DOPUS_PRESUME_NEON=ON -DRUNTIME_CPU_CAPABILITY_DETECTION=OFF) # every arm64 CPU has NEON
    if [ "$HOST" = Darwin ]; then
      configure_and_build "$BUILD/macos-$arch" -DCMAKE_OSX_ARCHITECTURES=$arch \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 "${neon[@]}"
    else
      zig_cmd >/dev/null || { echo "   needs Zig: pip install ziglang"; return 1; }
      local zt=aarch64-macos.11.0
      [ "$arch" = x86_64 ] && zt=x86_64-macos.11.0
      zig_wrappers $zt "$BUILD/zig-macos-$arch"
      # shellcheck disable=SC2046
      configure_and_build "$BUILD/macos-$arch" -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=$arch \
        $(zig_flags "$BUILD/zig-macos-$arch") "${neon[@]}"
    fi
  done
}

mkdir -p "$BUILD"
targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  case "$HOST" in
    Linux) targets=(linux windows macos) ;;
    Darwin) targets=(macos) ;;
    *) targets=(windows) ;;
  esac
fi
failed=0
for t in "${targets[@]}"; do
  "build_$t" || failed=1
done
ls -l addons/opus_voice/bin/
exit $failed
