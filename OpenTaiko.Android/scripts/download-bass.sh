#!/usr/bin/env bash
# Download BASS, BASSmix and BASS_FX for Android from un4seen.com and drop the per-ABI shared
# objects into jniLibs/ (the Linux/macOS counterpart of download-bass.ps1; keep both in sync).
#
# Usage: bash OpenTaiko.Android/scripts/download-bass.sh
#
# Every ABI listed here must end up with the libraries FDK imports: an AndroidNativeLibrary wildcard
# that matches nothing still packages an APK, which then aborts at boot on the missing lib.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JNI_DIR="$PROJECT_DIR/jniLibs"

# bass_fx is a third-party addon (Jobnik) hosted under files/z/0/ on un4seen.com
# "package name|url|shared object it provides"
PACKAGES=(
  "bass24-android|https://www.un4seen.com/files/bass24-android.zip|libbass.so"
  "bassmix24-android|https://www.un4seen.com/files/bassmix24-android.zip|libbassmix.so"
  "bass_fx24-android|https://www.un4seen.com/files/z/0/bass_fx24-android.zip|libbass_fx.so"
)
ABIS=("arm64-v8a" "x86_64")
REQUIRED=(libbass.so libbassmix.so libbass_fx.so)

download_package() {
  local name="$1" url="$2" provides="$3"
  local tmpdir dest src count so abi

  # build.ps1's rule: fetch only what is not there yet.
  local missing=0
  for abi in "${ABIS[@]}"; do
    [[ -f "$JNI_DIR/$abi/$provides" ]] || missing=1
  done
  if [[ $missing -eq 0 ]]; then
    echo "[download-bass] $name already unpacked, skipping"
    return 0
  fi

  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  echo "[download-bass] Downloading $name..."
  curl -sfL --retry 3 --retry-delay 5 "$url" -o "$tmpdir/package.zip"
  unzip -q "$tmpdir/package.zip" -d "$tmpdir/unpacked"

  for abi in "${ABIS[@]}"; do
    # un4seen zips carry the NDK layout (libs/<abi>/*.so); some nest it another level down.
    src="$(find "$tmpdir/unpacked" -type d -name "$abi" | head -1 || true)"
    if [[ -z "$src" ]]; then
      echo "[download-bass] ERROR: $name has no $abi directory" >&2
      return 1
    fi
    dest="$JNI_DIR/$abi"
    mkdir -p "$dest"
    count=0
    while IFS= read -r -d '' so; do
      cp -f "$so" "$dest/"
      echo "[download-bass]   $abi/$(basename "$so")"
      count=$((count + 1))
    done < <(find "$src" -maxdepth 1 -name '*.so' -print0)
    if [[ $count -eq 0 ]]; then
      echo "[download-bass] ERROR: no .so for $abi inside $name" >&2
      return 1
    fi
  done
}

mkdir -p "$JNI_DIR"
for entry in "${PACKAGES[@]}"; do
  IFS='|' read -r name url provides <<< "$entry"
  download_package "$name" "$url" "$provides"
done

for so in "${REQUIRED[@]}"; do
  for abi in "${ABIS[@]}"; do
    if [[ ! -f "$JNI_DIR/$abi/$so" ]]; then
      echo "[download-bass] ERROR: $abi/$so missing after download" >&2
      exit 1
    fi
  done
done

echo "[download-bass] Done. jniLibs/ now holds the BASS natives."
