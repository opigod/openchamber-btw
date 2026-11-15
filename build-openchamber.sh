#!/usr/bin/env bash
#
# Download the supported OpenChamber release, apply the stateless /btw fix, and
# build a system package or an Android APK.
#
# Home: https://github.com/opigod/openchamber-btw
#
#   ./build-openchamber.sh --target linux
#   ./build-openchamber.sh --target android
#   ./build-openchamber.sh --target all --install
#
# The patch is a plain `git diff` against the OpenChamber main branch. If
# upstream changes one of the touched files, `git apply --3way` may still
# resolve it. A real conflict stops the build and prints the source tree.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="${OPENCHAMBER_BTW_PATCH:-$SCRIPT_DIR/btw-stateless.patch}"
TARGET="linux"
INSTALL=0
REF="${OPENCHAMBER_REF:-v2.7.2}"
WORK_DIR="${OPENCHAMBER_BTW_WORKDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/openchamber-btw-builder}"
SRC_DIR="$WORK_DIR/source"
OUT_DIR="$WORK_DIR/out"
ANDROID_SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$WORK_DIR/android-sdk}}"
JDK_DIR="$WORK_DIR/jdk21"
CMDLINE_TOOLS_URL="${ANDROID_CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip}"
ANDROID_COMPILE_SDK="${ANDROID_COMPILE_SDK:-}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-}"
PATCH_BASE="1a151518c95cc5ff3578bab593d2f96862ff3bb8"

log() { printf '\n[openchamber-btw] %s\n' "$*"; }
die() { printf '\n[openchamber-btw] ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: build-openchamber.sh [options]

Options:
  --target linux|android|all   What to build (default: linux)
  --install                    Install the result (pacman package, and APK via adb)
  --ref REF                    OpenChamber branch or tag to build (default: v2.7.2, the patch base)
  --workdir DIR                Cache and build directory
  --patch FILE                 Path to btw-stateless.patch
  --help                       Show this help

Environment:
  OPENCHAMBER_REF              Same as --ref
  OPENCHAMBER_BTW_WORKDIR      Same as --workdir
  OPENCHAMBER_BTW_PATCH        Same as --patch
  ANDROID_HOME / ANDROID_SDK_ROOT
  JAVA_HOME
  ANDROID_CMDLINE_TOOLS_URL
  ANDROID_COMPILE_SDK          Read from variables.gradle when unset
  ANDROID_BUILD_TOOLS          Defaults to <compile-sdk>.0.0
  ANDROID_PLATFORM_PACKAGE     Override the SDK platform package

The Linux package is built with makepkg and installed with pacman through
pkexec. The Android build produces a debug APK and can install it with adb.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --workdir) WORK_DIR="${2:-}"; shift 2 ;;
    --patch) PATCH_FILE="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "$TARGET" in
  linux|android|all) ;;
  *) die "--target must be linux, android or all" ;;
esac

[[ -f "$PATCH_FILE" ]] || die "Patch file not found: $PATCH_FILE"

export PATH="$HOME/.bun/bin:$PATH"
mkdir -p "$WORK_DIR" "$OUT_DIR"

ensure_bun() {
  if have bun; then return; fi
  log "Installing Bun"
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  have bun || die "Bun was not installed"
}

ensure_base_tools() {
  local missing=()
  for tool in git curl tar unzip; do
    have "$tool" || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}. Install them with your package manager."
  fi
}

sync_source() {
  ensure_bun
  ensure_base_tools
  log "Fetching OpenChamber $REF into $SRC_DIR"
  if [[ ! -d "$SRC_DIR/.git" ]]; then
    rm -rf "$SRC_DIR"
    git clone --depth 1 --branch "$REF" https://github.com/openchamber/openchamber.git "$SRC_DIR"
  else
    git -C "$SRC_DIR" fetch --depth 1 origin "$REF"
    git -C "$SRC_DIR" reset --hard FETCH_HEAD
    # Remove files added by a previous patch. Ignored node_modules and build
    # caches stay in place.
    git -C "$SRC_DIR" clean -fd >/dev/null
  fi

  # `git apply --3way` needs the blobs the patch was made against. A shallow
  # clone of a newer main may not have them.
  if ! git -C "$SRC_DIR" cat-file -e "$PATCH_BASE^{commit}" 2>/dev/null; then
    git -C "$SRC_DIR" fetch --depth 1 origin "$PATCH_BASE" >/dev/null 2>&1 || true
  fi

  log "Applying $PATCH_FILE"
  if ! git -C "$SRC_DIR" apply --3way "$PATCH_FILE"; then
    die "The /btw patch no longer applies to $REF. Update $PATCH_FILE from the fork branch, or build the patch base with --ref v2.7.2."
  fi

  log "Installing dependencies"
  (cd "$SRC_DIR" && bun install --frozen-lockfile)

  local version
  version="$(cd "$SRC_DIR" && node -p "require('./packages/electron/package.json').version")"
  echo "$version" > "$WORK_DIR/version"
  log "OpenChamber $version ready at $SRC_DIR"
}

linux_package() {
  have makepkg || die "Linux package build needs makepkg (Arch-based distro)"
  have pacman || die "Linux package build needs pacman"
  local version
  version="$(cat "$WORK_DIR/version")"
  local pkgdir="$WORK_DIR/linux-pkg"
  rm -rf "$pkgdir"
  mkdir -p "$pkgdir"

  log "Building the Electron app directory"
  (cd "$SRC_DIR" && bun run --cwd packages/electron package -- --linux dir)

  local app_dir="$SRC_DIR/packages/electron/dist/linux-unpacked"
  [[ -x "$app_dir/openchamber" ]] || die "Electron build did not produce $app_dir/openchamber"

  cat > "$pkgdir/PKGBUILD" <<PKGBUILD
pkgname=openchamber-btw
pkgver=$version
pkgrel=1
pkgdesc="OpenChamber desktop runtime with the stateless /btw side question"
arch=('x86_64')
url="https://openchamber.dev"
license=('MIT')
depends=('gtk3' 'nss' 'libxss' 'libnotify' 'libxtst' 'libsecret' 'alsa-lib' 'libcups' 'libdrm' 'mesa' 'libxcomposite' 'libxdamage' 'libxrandr' 'at-spi2-core' 'pango' 'cairo' 'gdk-pixbuf2' 'nspr' 'libglvnd' 'xdg-utils')
conflicts=('openchamber-custom')
replaces=('openchamber-custom')
options=(!strip)
package() {
  install -d "\$pkgdir/opt/openchamber"
  cp -a "$app_dir/." "\$pkgdir/opt/openchamber/"

  install -d "\$pkgdir/usr/bin"
  ln -s /opt/openchamber/openchamber "\$pkgdir/usr/bin/openchamber"

  install -d "\$pkgdir/usr/share/applications"
  cat > "\$pkgdir/usr/share/applications/openchamber.desktop" <<'DESKTOP'
[Desktop Entry]
Name=OpenChamber
Comment=Desktop runtime for OpenChamber
Exec=/opt/openchamber/openchamber --no-sandbox %U
TryExec=/opt/openchamber/openchamber
Terminal=false
Type=Application
Icon=openchamber
StartupWMClass=openchamber
Categories=Development;
DESKTOP

  install -Dm644 "$SRC_DIR/packages/electron/resources/icons/app-icon.png" "\$pkgdir/usr/share/icons/hicolor/512x512/apps/openchamber.png"
  install -Dm644 "$SRC_DIR/LICENSE" "\$pkgdir/usr/share/licenses/\$pkgname/LICENSE"
}
PKGBUILD

  log "Building pacman package"
  (cd "$pkgdir" && makepkg -f)

  local package
  package="$(find "$pkgdir" -maxdepth 1 -name 'openchamber-btw-*.pkg.tar.*' -print -quit)"
  [[ -n "$package" ]] || die "makepkg did not produce a package"
  cp -f "$package" "$OUT_DIR/"
  log "Linux package: $OUT_DIR/$(basename "$package")"

  if [[ "$INSTALL" -eq 1 ]]; then
    have pkexec || die "Installing the package needs pkexec"
    # pacman refuses to replace a package that `conflicts` with the new one
    # even under --noconfirm. Remove it first, in one transaction.
    local installed=()
    local name
    for name in openchamber-btw openchamber-custom; do
      if pacman -Q "$name" >/dev/null 2>&1; then
        installed+=("$name")
      fi
    done
    if [[ ${#installed[@]} -gt 0 ]]; then
      log "Removing installed package(s): ${installed[*]}"
      pkexec pacman -Rns --noconfirm "${installed[@]}"
    fi
    log "Installing with pacman through polkit"
    pkexec pacman -U --noconfirm "$package"
    log "Installed. Launch with: openchamber"
  else
    log "Not installed. Re-run with --install, or run: sudo pacman -U '$package'"
  fi
}

ensure_jdk21() {
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    local current
    current="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
    if [[ "$current" == *'"21.'* || "$current" == *' 21.'* ]]; then
      log "Using JDK 21: $JAVA_HOME"
      export PATH="$JAVA_HOME/bin:$PATH"
      return
    fi
  fi

  for candidate in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-21-temurin /usr/lib/jvm/temurin-21-jdk; do
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      export PATH="$JAVA_HOME/bin:$PATH"
      log "Using JDK 21: $JAVA_HOME"
      return
    fi
  done

  if [[ ! -x "$JDK_DIR/bin/java" ]]; then
    log "Downloading Temurin JDK 21"
    rm -rf "$JDK_DIR" "$WORK_DIR/jdk21.tar.gz"
    curl -fL --retry 3 -o "$WORK_DIR/jdk21.tar.gz" \
      "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
    mkdir -p "$JDK_DIR"
    tar -xzf "$WORK_DIR/jdk21.tar.gz" -C "$JDK_DIR" --strip-components=1
    rm -f "$WORK_DIR/jdk21.tar.gz"
  fi
  [[ -x "$JDK_DIR/bin/java" ]] || die "JDK 21 download failed"
  export JAVA_HOME="$JDK_DIR"
  export PATH="$JAVA_HOME/bin:$PATH"
  log "Using JDK 21: $JAVA_HOME"
}

ensure_android_sdk() {
  if [[ -z "$ANDROID_COMPILE_SDK" ]]; then
    ANDROID_COMPILE_SDK="$(sed -n 's/.*compileSdkVersion = \([0-9][0-9]*\).*/\1/p' "$SRC_DIR/packages/mobile/android/variables.gradle" | head -1)"
    ANDROID_COMPILE_SDK="${ANDROID_COMPILE_SDK:-35}"
  fi
  local sdk_major="${ANDROID_COMPILE_SDK%%.*}"
  if [[ -z "$ANDROID_BUILD_TOOLS" ]]; then
    ANDROID_BUILD_TOOLS="${sdk_major}.0.0"
  fi
  local sdkmanager="$ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
  if [[ ! -x "$sdkmanager" ]]; then
    log "Downloading Android command-line tools"
    rm -rf "$WORK_DIR/android-cmdline-tools" "$WORK_DIR/android-cmdline-tools.zip"
    curl -fL --retry 3 -o "$WORK_DIR/android-cmdline-tools.zip" "$CMDLINE_TOOLS_URL"
    mkdir -p "$WORK_DIR/android-cmdline-tools"
    unzip -q "$WORK_DIR/android-cmdline-tools.zip" -d "$WORK_DIR/android-cmdline-tools"
    rm -f "$WORK_DIR/android-cmdline-tools.zip"
    mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"
    rm -rf "$ANDROID_SDK_DIR/cmdline-tools/latest"
    mv "$WORK_DIR/android-cmdline-tools/cmdline-tools" "$ANDROID_SDK_DIR/cmdline-tools/latest"
    rm -rf "$WORK_DIR/android-cmdline-tools"
  fi

  export ANDROID_HOME="$ANDROID_SDK_DIR"
  export ANDROID_SDK_ROOT="$ANDROID_SDK_DIR"
  export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

  mkdir -p "$HOME/.android"
  touch "$HOME/.android/repositories.cfg"

  # SDK 35 and older use `platforms;android-35`; from 36 on, minor releases
  # exist and the package is `platforms;android-37.0`. Ask the repository
  # rather than guessing. An explicit ANDROID_PLATFORM_PACKAGE wins.
  local platform_pkg="${ANDROID_PLATFORM_PACKAGE:-}"
  if [[ -z "$platform_pkg" ]]; then
    local packages
    packages="$("$sdkmanager" --sdk_root="$ANDROID_HOME" --list 2>/dev/null | sed -n 's/^  \(platforms;android-[0-9][^ |]*\).*/\1/p' | sort -u)"
    local candidate
    for candidate in \
      "platforms;android-$ANDROID_COMPILE_SDK" \
      "platforms;android-$sdk_major.0" \
      $(printf '%s\n' "$packages" | grep -E "^platforms;android-$sdk_major(\.|$)" | sort -V -r); do
      if printf '%s\n' "$packages" | grep -qxF "$candidate"; then
        platform_pkg="$candidate"
        break
      fi
    done
    platform_pkg="${platform_pkg:-platforms;android-$ANDROID_COMPILE_SDK}"
  fi

  local have_platform=0
  compgen -G "$ANDROID_HOME/platforms/android-$ANDROID_COMPILE_SDK*" >/dev/null && have_platform=1

  if [[ "$have_platform" -eq 0 || ! -d "$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS" ]]; then
    log "Installing Android SDK $ANDROID_COMPILE_SDK ($platform_pkg) and build-tools $ANDROID_BUILD_TOOLS"
    (set +o pipefail; yes | "$sdkmanager" --sdk_root="$ANDROID_HOME" --licenses >/dev/null) || true
    "$sdkmanager" --sdk_root="$ANDROID_HOME" --install \
      "platform-tools" \
      "$platform_pkg" \
      "build-tools;$ANDROID_BUILD_TOOLS"
  fi
  log "Using Android SDK: $ANDROID_HOME"
}

android_apk() {
  ensure_jdk21
  ensure_android_sdk
  local version
  version="$(cat "$WORK_DIR/version")"

  log "Building the mobile web UI and Android debug APK"
  (cd "$SRC_DIR" && bun run --cwd packages/mobile build:android:debug)

  local apk="$SRC_DIR/packages/mobile/android/app/build/outputs/apk/debug/app-debug.apk"
  [[ -f "$apk" ]] || die "Android build did not produce $apk"
  local output="$OUT_DIR/OpenChamber-btw-${version}-android-debug.apk"
  cp -f "$apk" "$output"
  log "Android APK: $output"

  if [[ "$INSTALL" -eq 1 ]]; then
    have adb || die "Installing the APK needs adb"
    local device
    device="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
    if [[ -z "$device" ]]; then
      log "No adb device is connected. APK left at $output"
      return
    fi
    log "Installing on Android device $device"
    adb -s "$device" install -r "$output"
    log "Installed. Open the OpenChamber app and connect it to your OpenChamber server."
  else
    log "Not installed. Connect a device and run: adb install -r '$output'"
  fi
}

log "Work directory: $WORK_DIR"
sync_source

if [[ "$TARGET" == "linux" || "$TARGET" == "all" ]]; then
  linux_package
fi
if [[ "$TARGET" == "android" || "$TARGET" == "all" ]]; then
  android_apk
fi

log "Done. Outputs are in $OUT_DIR"
