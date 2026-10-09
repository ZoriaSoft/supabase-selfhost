#!/usr/bin/env bash
# Path A — download a prebuilt GoTrue (supabase/auth) binary and scaffold
# a loopback-ready env file. No Docker. Requires: curl, tar, xz/gzip, a
# reachable Postgres (you bring that). See README "Yol A" + SECURITY.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${GOTRUE_DIR:-$REPO_ROOT/bin}"
ENV_OUT="${GOTRUE_ENV:-$REPO_ROOT/gotrue.env}"
TAG="${GOTRUE_VERSION:-v2.197.0}"  # pinned default (matches bin/gotrue); override via GOTRUE_VERSION
SHA256_EXPECTED="${GOTRUE_SHA256:-}"  # when set, overrides the pinned hash below

# Pinned sha256 of each release asset for the default tag.
# The supabase/auth release publishes no checksums file, so these were
# computed on first download (trust-on-first-use, 2026-10-09).
declare -A PINNED_SHA256=(
  [auth-v2.197.0-amd64.tar.xz]=b5c2991d1df760c9b099c1c2395a94bd1c2f83ed58901934921997179dc9f7ea
  [auth-v2.197.0-arm64.tar.xz]=a9da2e668137cb280c830d900df4081b3fdd42a289469485634426a7587f9f76
  [auth-v2.197.0-darwin-arm64.tar.gz]=3fb7998e7061e2c14f3f9555b1d94d447358c965395728e0d81eac82e0e5868b
  [auth-v2.197.0-x86.tar.gz]=9daff5d1939c3142a1586e435e6e2a7a2f71534ec40ff1b196b59b83ad5678f3
)

arch_norm() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    i386|i686|x86) echo x86 ;;
    *) echo "unsupported arch: $m" >&2; exit 1 ;;
  esac
}

os_norm() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo darwin ;;
    *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
}

pick_asset() {
  # stdin: release JSON from GitHub API; args: arch
  local arch="$1" os
  os="$(os_norm)"
  # Prefer .tar.xz; asset naming: auth-vX.Y.Z-{amd64|arm64|x86|darwin-arm64}.tar.{xz,gz}
  if [ "$os" = darwin ] && [ "$arch" = arm64 ]; then
    echo "auth-.*-darwin-arm64\\.tar\\.(xz|gz)"
  elif [ "$os" = darwin ]; then
    echo "no prebuilt darwin-amd64 asset in current supabase/auth releases" >&2
    exit 1
  elif [ "$arch" = amd64 ]; then
    echo "auth-.*-amd64\\.tar\\.(xz|gz)"
  elif [ "$arch" = arm64 ]; then
    echo "auth-.*-arm64\\.tar\\.(xz|gz)"
  else
    echo "auth-.*-x86\\.tar\\.(xz|gz)"
  fi
}

latest_stable_tag() {
  curl -fsSL "https://api.github.com/repos/supabase/auth/releases?per_page=20" \
    | python3 -c '
import json,sys
rels=json.load(sys.stdin)
for r in rels:
    tag=r.get("tag_name") or ""
    if r.get("prerelease") or r.get("draft"): continue
    if tag.startswith("rc") or "-rc" in tag: continue
    if tag.startswith("v") and r.get("assets"):
        print(tag); break
else:
    sys.exit("no stable supabase/auth release with assets found")
'
}

release_json() {
  local tag="$1"
  curl -fsSL "https://api.github.com/repos/supabase/auth/releases/tags/${tag}"
}

main() {
  local arch asset_re tag json name url
  arch="$(arch_norm)"
  tag="${TAG:-$(latest_stable_tag)}"
  echo "==> GoTrue Path A setup"
  echo "    version : $tag"
  echo "    arch    : $arch ($(os_norm))"
  echo "    dest    : $DEST_DIR"

  json="$(release_json "$tag")"
  asset_re="$(pick_asset "$arch")"
  # Prefer xz over gz when both match.
  read -r name url <<EOF2
$(printf '%s' "$json" | python3 -c '
import json,sys,re
arch_re=sys.argv[1]
data=json.load(sys.stdin)
assets=data.get("assets") or []
xz=gz=None
for a in assets:
    n=a.get("name") or ""
    if re.search(arch_re, n):
        if n.endswith(".tar.xz"): xz=a
        elif n.endswith(".tar.gz"): gz=a
pick=xz or gz
if not pick:
    sys.exit(f"no matching asset for /{arch_re}/ in release")
print(pick["name"], pick["browser_download_url"])
' "$asset_re")
EOF2

  mkdir -p "$DEST_DIR"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  # Integrity is mandatory. The default tag verifies against the pinned
  # hashes above; any other GOTRUE_VERSION requires GOTRUE_SHA256.
  local expected=""
  if [ -n "$SHA256_EXPECTED" ]; then
    expected="$SHA256_EXPECTED"
  elif [ "$tag" = "v2.197.0" ]; then
    expected="${PINNED_SHA256[$name]:-}"
    if [ -z "$expected" ]; then
      echo "no pinned sha256 for asset $name — pass GOTRUE_SHA256 explicitly" >&2
      exit 1
    fi
  else
    echo "GOTRUE_VERSION=$tag has no pinned checksum — refusing to install an" >&2
    echo "unverified auth binary. Get the asset's sha256 and re-run with:" >&2
    echo "    GOTRUE_SHA256=<sha256> $0" >&2
    exit 1
  fi
  echo "==> downloading $name"
  curl -fL --progress-bar -o "$tmp/$name" "$url"
  echo "$expected  $tmp/$name" | sha256sum -c - \
    || { echo "sha256 mismatch for $name — refusing to install" >&2; exit 1; }
  echo "    sha256 verified"
  echo "==> extracting"
  case "$name" in
    *.tar.xz) tar -xJf "$tmp/$name" -C "$tmp" ;;
    *.tar.gz) tar -xzf "$tmp/$name" -C "$tmp" ;;
    *) echo "unexpected asset type: $name" >&2; exit 1 ;;
  esac
  # Binary may be named `auth` or `gotrue`
  local bin=""
  for cand in "$tmp/auth" "$tmp/gotrue"; do
    if [ -f "$cand" ]; then
      bin="$cand"
      break
    fi
  done
  if [ -z "$bin" ]; then
    bin="$(find "$tmp" -maxdepth 2 -type f \( -name auth -o -name gotrue \) | head -1)"
  fi
  [ -n "$bin" ] || { echo "binary not found in archive" >&2; exit 1; }
  install -m 755 "$bin" "$DEST_DIR/gotrue"
  echo "    installed $DEST_DIR/gotrue"
  rm -rf "$tmp"

  if [ ! -f "$ENV_OUT" ]; then
    cp "$REPO_ROOT/scripts/gotrue.env.example" "$ENV_OUT"
    chmod 600 "$ENV_OUT"
    echo "    wrote $ENV_OUT (chmod 600) — edit secrets before starting"
  else
    echo "    keeping existing $ENV_OUT"
  fi

  cat <<MSG

Next steps (Path A — Auth only, no Docker):
  1. Create a least-privilege DB role (edit password first):
       psql -f $REPO_ROOT/scripts/create-auth-role.sql
  2. Edit $ENV_OUT — set GOTRUE_DB_DATABASE_URL, GOTRUE_JWT_SECRET,
     GOTRUE_SITE_URL, GOTRUE_JWT_ISSUER / API_EXTERNAL_URL.
  3. Apply migrations, then start on loopback:
       set -a; . $ENV_OUT; set +a
       $DEST_DIR/gotrue migrate   # required on first boot
       $DEST_DIR/gotrue
  4. Put a TLS-terminating reverse proxy in front (never expose :9999
     on a public interface). See SECURITY.md.

Zo Computer is a gVisor sandbox: Docker containers do not run there.
Path A (this script / binary GoTrue) is the Zo-compatible path.
Path B (./setup.sh, docker compose) needs a real-kernel VPS only.
This script does not start Postgres and does not claim Docker works on Zo.
MSG
}

main "$@"
