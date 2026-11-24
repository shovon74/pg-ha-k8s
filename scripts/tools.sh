#!/usr/bin/env bash
# Installs pinned kubectl and k3d into ./bin. A binary is installed only after its SHA-256 matches.
. "$(dirname "$0")/lib.sh"
mkdir -p "$BIN_DIR"

install_tool() { # name url sha256
  local name=$1 url=$2 sum=$3 dest="$BIN_DIR/$1" tmp
  if [ -x "$dest" ] && echo "$sum  $dest" | sha256sum -c --status; then
    log "OK    $name already installed, checksum matches"; return
  fi
  tmp=$(mktemp "$BIN_DIR/.$name.XXXXXX"); trap 'rm -f "$tmp"' RETURN
  log "GET   $name from $url"
  curl -fsSL --retry 3 --max-time 300 -o "$tmp" "$url"
  echo "$sum  $tmp" | sha256sum -c --status || die "$name checksum mismatch, not installed"
  chmod 0755 "$tmp"; mv "$tmp" "$dest"
  log "OK    $name installed, checksum verified"
}

install_tool kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" "$KUBECTL_SHA256"
install_tool k3d "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-amd64" "$K3D_SHA256"
