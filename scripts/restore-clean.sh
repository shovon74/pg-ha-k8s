#!/usr/bin/env bash
# L4: deletes the restored cluster: only the pg-restore namespace and its PVCs. Refuses any other namespace.
. "$(dirname "$0")/lib.sh"
NS=${NS:-pg-restore}
[ "$NS" = pg-restore ] || die "restore-clean deletes only namespace pg-restore, not $NS"
kubectl get ns "$NS" >/dev/null 2>&1 || { log "namespace $NS does not exist, nothing to delete"; exit 0; }
kubectl -n "$NS" delete statefulset --all --wait=true >/dev/null
kubectl -n "$NS" delete pvc --all --wait=true
kubectl delete ns "$NS" --wait=true
rm -f "$ROOT_DIR/deploy/restore/30-restore.yml"
log "deleted namespace $NS and its PVCs"
