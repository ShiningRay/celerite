#!/usr/bin/env bash
# Celerite installer — curl | bash (roadmap M6).
#
#   curl -fsSL https://github.com/ShiningRay/celerite/releases/latest/download/install.sh | bash
#
# Downloads the platform binary from GitHub Releases, verifies its SHA-256
# checksum against the release's checksums.sha256, and installs:
#   $PREFIX/celerite           (the engine)
#   $PREFIX/bundle             (bundle shim — ONLY if no `bundle` exists on
#   PATH; otherwise `celerite-bundle`, opt-in, nothing replaced)
#
# Environment / flags:
#   PREFIX=<dir>               install prefix (default ~/.local/bin)
#   CELERITE_INSTALL_VERSION   pin a version, e.g. 0.1.0 (default: latest)
#   CELERITE_RELEASE_URL       override release base URL (file:// supported
#                              for offline testing; must point at a dir of
#                              v<version>/ subdirs)
#   --prefix <dir>             same as PREFIX
#   <version>                  positional version pin (e.g. 0.1.0)
set -euo pipefail

repo="ShiningRay/celerite"
base="${CELERITE_RELEASE_URL:-https://github.com/$repo/releases}"
prefix="${PREFIX:-$HOME/.local/bin}"
requested="${CELERITE_INSTALL_VERSION:-}"
mode_tag=""

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) [ $# -ge 2 ] || die "--prefix needs a value"; prefix="$2"; shift 2 ;;
    --prefix=*) prefix="${1#--prefix=}"; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *) requested="$1"; shift ;;
  esac
done

need curl
need mktemp
if command -v sha256sum >/dev/null 2>&1; then
  checksum_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  checksum_cmd="shasum -a 256"
else
  die "missing dependency: sha256sum or shasum"
fi

# --- platform triple (must match script/release asset naming) --------------
case "$(uname -s)" in
  Linux) os="linux" ;;
  Darwin) os="macos" ;;
  MINGW* | MSYS* | CYGWIN*) os="windows" ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac
arch="$(uname -m)"
triple="$os-$arch"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- release base resolution -----------------------------------------------
# file:// bases are test/offline mode: a plain directory with v<version>/
# subdirs, no /download/ segment and no redirects.
if [ "${base#file://}" != "$base" ]; then
  base="${base%/}"
  if [ -z "$requested" ]; then
    # plain-directory layout: ls needs the filesystem path, not the URL
    fs_base="${base#file://}"
    latest_dir="$(ls -1d "$fs_base"/v* 2>/dev/null | sort -V | tail -1)"
    [ -n "${latest_dir:-}" ] || die "no v* release dirs under $base"
    requested="${latest_dir##*/v}"
  fi
  sum_url="$base/v$requested/checksums.sha256"
  asset_url() { printf '%s/v%s/%s' "$base" "$1" "$2"; }
else
  base="${base%/}"
  if [ -n "$requested" ]; then
    sum_url="$base/download/v$requested/checksums.sha256"
    asset_url() { printf '%s/download/v%s/%s' "$base" "$1" "$2"; }
  else
    # latest: the checksums asset carries canonical file names
    # (celerite-<version>-<os>-<arch>), so it doubles as the version probe
    sum_url="$base/latest/download/checksums.sha256"
    asset_url() { printf '%s/download/v%s/%s' "$base" "$1" "$2"; }
  fi
fi

curl -fsSL "$sum_url" -o "$tmp/checksums.sha256" || die "cannot fetch $sum_url"

if [ -z "$requested" ]; then
  # checksum lines are "<hash>  <name>" (coreutils text) or "<hash> *<name>"
  # (binary marker, e.g. Git Bash) — tolerate both
  target="$(grep -E -- "-$triple\$" "$tmp/checksums.sha256" | head -n1 | awk '{sub(/^\*/, "", $2); print $2}')"
  [ -n "$target" ] || die "no release asset for platform $triple"
  mode_tag="${target#celerite-}"; mode_tag="${mode_tag%%-*}"
else
  target="celerite-$requested-$triple"
  mode_tag="$requested"
  grep -E -- " [*]?$target\$" "$tmp/checksums.sha256" >/dev/null \
    || die "release v$requested has no asset for platform $triple"
fi

say "Installing celerite $mode_tag for $triple -> $prefix"

# --- download + verify ------------------------------------------------------
curl -fsSL "$(asset_url "$mode_tag" "$target")" -o "$tmp/$target" \
  || die "cannot fetch $target"
(
  cd "$tmp"
  grep -E -- " [*]?$target\$" checksums.sha256 | $checksum_cmd -c - >/dev/null
) || die "checksum mismatch for $target (refusing to install)"
chmod 0755 "$tmp/$target"

# --- install (never replaces an existing bundle) ----------------------------
mkdir -p "$prefix"
mv "$tmp/$target" "$prefix/celerite"

shim_src="$(asset_url "$mode_tag" bundle)"
install_shim() {
  local dest="$1"
  if curl -fsSL "$shim_src" -o "$tmp/bundle"; then
    chmod 0755 "$tmp/bundle"
    mv "$tmp/bundle" "$dest"
  else
    say "WARNING: could not fetch the bundle shim (engine install succeeded)"
  fi
}

if command -v bundle >/dev/null 2>&1; then
  install_shim "$prefix/celerite-bundle"
  say "NOTE: an existing \`bundle\` was found on PATH — the shim was installed as \`celerite-bundle\` (opt-in only, nothing replaced)."
else
  install_shim "$prefix/bundle"
  say "Installed celerite bundle shim as \`$prefix/bundle\`."
fi

case ":$PATH:" in
  *":$prefix:"*) ;;
  *) say ""
     say "Add $prefix to your PATH to use \`celerite\`."
     ;;
esac
say "Verify with: celerite version"
