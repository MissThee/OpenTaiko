#!/usr/bin/env bash
# Download the FFmpeg 5.1.2 shared libraries for Android (Bytedeco/JavaCPP builds, LGPL base
# artifact, ABI-compatible with the FFmpeg.AutoGen 5.1.1 binding) from Maven Central and unpack the
# per-ABI objects into jniLibs/. Linux/macOS counterpart of download-ffmpeg.ps1; keep both in sync.
#
# Usage: bash OpenTaiko.Android/scripts/download-ffmpeg.sh
#
# Only the libraries the game decodes with are extracted: avformat/avcodec/avutil/swscale +
# swresample (avcodec dependency). Their SONAMEs and DT_NEEDED entries are unversioned and only
# reference NDK-public system libs (libm/libc/libdl), so they drop straight into an APK.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JNI_DIR="$PROJECT_DIR/jniLibs"

VERSION="5.1.2-1.5.8"
BASE="https://repo1.maven.org/maven2/org/bytedeco/ffmpeg/$VERSION"
WANTED=(libavutil.so libswresample.so libavcodec.so libavformat.so libswscale.so)
# "maven-classifier|jniLibs abi"
ABIS=("android-arm64|arm64-v8a" "android-x86_64|x86_64")

extract_abi() {
  local classifier="$1" abi="$2"
  local tmpdir jar dest name path missing=0

  # Same skip rule as build.ps1: fetch only what is not there yet.
  for name in "${WANTED[@]}"; do
    [[ -f "$JNI_DIR/$abi/$name" ]] || missing=1
  done
  if [[ $missing -eq 0 ]]; then
    echo "[download-ffmpeg] $abi already populated, skipping"
    return 0
  fi

  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  jar="$tmpdir/ffmpeg.jar"
  echo "[download-ffmpeg] Downloading ffmpeg $VERSION $classifier..."
  curl -sfL --retry 3 --retry-delay 5 "$BASE/ffmpeg-$VERSION-$classifier.jar" -o "$jar"

  dest="$JNI_DIR/$abi"
  mkdir -p "$dest"
  for name in "${WANTED[@]}"; do
    # Same rule as the PowerShell version: the first entry of that basename anywhere in the jar
    # (bytedeco nests them under <classifier>/).
    path="$(unzip -Z1 "$jar" | grep -E "(^|/)$name\$" | head -1 || true)"
    if [[ -z "$path" ]]; then
      echo "[download-ffmpeg] ERROR: $name not found in the $classifier jar" >&2
      return 1
    fi
    unzip -p "$jar" "$path" > "$dest/$name"
    echo "[download-ffmpeg]   $abi/$name"
  done
}

mkdir -p "$JNI_DIR"
for entry in "${ABIS[@]}"; do
  extract_abi "${entry%%|*}" "${entry#*|}"
done

for abi in "${ABIS[@]}"; do
  for name in "${WANTED[@]}"; do
    if [[ ! -f "$JNI_DIR/$abi/$name" ]]; then
      echo "[download-ffmpeg] ERROR: $abi/$name missing" >&2
      exit 1
    fi
  done
done

echo "[download-ffmpeg] Done. jniLibs/ now holds the FFmpeg natives."
