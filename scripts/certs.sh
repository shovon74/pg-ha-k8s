#!/usr/bin/env bash
# One private CA plus Postgres and pgBackRest certs (ADR-009, ADR-012). Never overwrites.
. "$(dirname "$0")/lib.sh"
umask 077
D="$SECRETS_DIR/tls"; mkdir -p "$D"; chmod 700 "$SECRETS_DIR" "$D"

# Namespaces the certs must be valid in: the main one and the restore target (R5.1).
NAMESPACES="pg-ha pg-restore"
san="DNS:localhost,IP:127.0.0.1"
for ns in $NAMESPACES; do
  san="$san,DNS:*.pg-headless.$ns.svc.cluster.local,DNS:*.pg-headless.$ns.svc"
  san="$san,DNS:pg-rw.$ns.svc.cluster.local,DNS:pg-rw.$ns.svc,DNS:pg-ro.$ns.svc.cluster.local,DNS:pg-ro.$ns.svc"
done

if [ -s "$D/ca.key" ] && [ -s "$D/ca.crt" ]; then log "OK    CA exists, kept"
elif [ -e "$D/ca.key" ] || [ -e "$D/ca.crt" ]; then die "partial CA in $D, refusing to overwrite"
else
  openssl ecparam -name prime256v1 -genkey -noout -out "$D/ca.key"
  openssl req -x509 -new -sha256 -key "$D/ca.key" -days 3650 -subj "/CN=pg-ha-k8s private CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" -out "$D/ca.crt"
  log "NEW   CA created"
fi

issue() { # name CN extendedKeyUsage SAN(optional)
  local n=$1 cn=$2 eku=$3 s=${4:-} ext
  if [ -s "$D/$n.key" ] && [ -s "$D/$n.crt" ]; then log "OK    $n exists, kept"; return; fi
  [ ! -e "$D/$n.key" ] && [ ! -e "$D/$n.crt" ] || die "partial $n in $D, refusing to overwrite"
  ext=$(mktemp)
  { echo "basicConstraints=critical,CA:FALSE"; echo "keyUsage=critical,digitalSignature"
    echo "extendedKeyUsage=$eku"; [ -z "$s" ] || echo "subjectAltName=$s"; } > "$ext"
  openssl ecparam -name prime256v1 -genkey -noout -out "$D/$n.key.tmp"
  openssl req -new -sha256 -key "$D/$n.key.tmp" -subj "/CN=$cn" |
    openssl x509 -req -sha256 -CA "$D/ca.crt" -CAkey "$D/ca.key" -CAcreateserial -days 825 \
      -extfile "$ext" -out "$D/$n.crt" 2>/dev/null
  mv "$D/$n.key.tmp" "$D/$n.key"; rm -f "$ext"
  log "NEW   $n issued (CN=$cn)"
}

issue postgres-server pg-ha-postgres serverAuth "$san"
issue pgbackrest-server pg-ha-pgbackrest serverAuth "$san"
# pgBackRest's TLS server authorises callers by client-certificate CN.
issue pgbackrest-client pgbackrest-client clientAuth
chmod 600 "$D"/*
for n in postgres-server pgbackrest-server pgbackrest-client; do
  openssl verify -CAfile "$D/ca.crt" "$D/$n.crt" >/dev/null || die "$n does not verify against the CA"
done
log "Certs verified against the CA (in ./secrets/tls)"
