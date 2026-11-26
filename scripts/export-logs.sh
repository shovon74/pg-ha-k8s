#!/usr/bin/env bash
# L8 (R11.2, R11.7, D5): export this project's Claude Code session logs into ai-logs/raw/, redacted.
#
# 1. Copies every session JSONL for this project from ~/.claude/projects/<project-dir>/ into ai-logs/raw/.
# 2. Applies the redactions listed in docs/process/redaction-log.md, plus email addresses, GCP project ID and
#    number, the VM's external IP and hostname, any other public IPv4 address, the home path and the username.
#    Every replacement is a visible placeholder such as [REDACTED-EMAIL]. Counts per rule and file are written
#    to ai-logs/redactions.tsv (counts only, never values).
# 3. Scans the output for every value in ./secrets (credentials and private-key lines), by value, without
#    printing any value. Exits non-zero if one is found, and leaves the matching file names in the report.
# 4. Writes ai-logs/README.md, mapping each session file to its phase.
#
# Run it after the last session has ended, so that session is included. It only reads ~/.claude and only
# writes under ai-logs/. Identifiers are read locally (env, gcloud config, the GCE metadata server); nothing
# is sent anywhere. Overrides: GCP_PROJECT_ID, GCP_PROJECT_NUMBER, EXTERNAL_IP, VM_HOSTNAME.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${CLAUDE_PROJECT_LOGS:-$HOME/.claude/projects/$(printf '%s' "$ROOT_DIR" | tr '/' '-')}"
OUT_DIR="$ROOT_DIR/ai-logs"
RAW_DIR="$OUT_DIR/raw"
SECRETS_DIR="$ROOT_DIR/secrets"

[ -d "$SRC_DIR" ] || { echo "ERROR: no session logs at $SRC_DIR" >&2; exit 1; }
[ -d "$SECRETS_DIR" ] || { echo "ERROR: ./secrets not found; it is needed for the secret scan" >&2; exit 1; }

md() { curl -fsS -m 2 -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/$1" 2>/dev/null || true; }
GCP_PROJECT_ID="${GCP_PROJECT_ID:-$( (command -v gcloud >/dev/null && gcloud config get-value project 2>/dev/null) || true)}"
[ -n "$GCP_PROJECT_ID" ] && [ "$GCP_PROJECT_ID" != "(unset)" ] || GCP_PROJECT_ID="$(md project/project-id)"
GCP_PROJECT_NUMBER="${GCP_PROJECT_NUMBER:-$(md project/numeric-project-id)}"
EXTERNAL_IP="${EXTERNAL_IP:-$(md instance/network-interfaces/0/access-configs/0/external-ip)}"
VM_HOSTNAME="${VM_HOSTNAME:-$(hostname)}"
export GCP_PROJECT_ID GCP_PROJECT_NUMBER EXTERNAL_IP VM_HOSTNAME
export HOME_DIR="$HOME" USER_NAME="$(id -un)"

mkdir -p "$RAW_DIR"
shopt -s nullglob
files=("$SRC_DIR"/*.jsonl)
[ "${#files[@]}" -gt 0 ] || { echo "ERROR: no .jsonl files in $SRC_DIR" >&2; exit 1; }

python3 -I - "$RAW_DIR" "$OUT_DIR/redactions.tsv" "${files[@]}" <<'PY'
import ipaddress, os, re, sys
raw_dir, report = sys.argv[1], sys.argv[2]
srcs = sys.argv[3:]
env = os.environ

rules = []  # (name, compiled regex, placeholder or function)
def lit(name, value, placeholder):
    if value and len(value) >= 3:
        rules.append((name, re.compile(re.escape(value)), placeholder))

# From docs/process/redaction-log.md: R-001, R-002 (rotated Garage S3 access key ID).
rules.append(("R-001/R-002 garage-s3-access-key-id", re.compile(r"GK[0-9a-f]{24}"), "[REDACTED:garage-s3-access-key-id]"))
# Cloud identifiers, most specific first.
lit("gcp-project-id", env.get("GCP_PROJECT_ID", ""), "[REDACTED-GCP-PROJECT]")
lit("gcp-project-number", env.get("GCP_PROJECT_NUMBER", ""), "[REDACTED-GCP-PROJECT-NUMBER]")
rules.append(("gcp-project-path", re.compile(r"(?<=projects/)[a-z][a-z0-9-]{4,28}[a-z0-9](?=[/\"\s])"), "[REDACTED-GCP-PROJECT]"))
lit("external-ip", env.get("EXTERNAL_IP", ""), "[REDACTED-EXTERNAL-IP]")
# Personal identifiers. The home path before the username, so the path keeps one placeholder.
rules.append(("email", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"), "[REDACTED-EMAIL]"))
lit("home-path", env.get("HOME_DIR", ""), "[REDACTED-HOME]")
lit("vm-hostname", env.get("VM_HOSTNAME", ""), "[REDACTED-HOST]")
lit("username", env.get("USER_NAME", ""), "[REDACTED-USER]")

# Any other public IPv4 address. Private, loopback, link-local, multicast, reserved and documentation
# ranges are kept (cluster and pod addresses carry meaning in the logs).
ipv4 = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
def public_ip(m):
    s = m.group(0)
    try:
        ip = ipaddress.IPv4Address(s)
    except ValueError:
        return s
    if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved or ip.is_unspecified \
            or ip in ipaddress.IPv4Network("100.64.0.0/10"):
        return s
    return "[REDACTED-EXTERNAL-IP]"
rules.append(("public-ipv4", ipv4, public_ip))

rows = []
for src in srcs:
    name = os.path.basename(src)
    with open(src, encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()
    for rname, rx, repl in rules:
        if callable(repl):
            count = [0]
            def sub(m, repl=repl, count=count):
                out = repl(m)
                if out != m.group(0):
                    count[0] += 1
                return out
            text = rx.sub(sub, text); n = count[0]
        else:
            text, n = rx.subn(repl, text)
        if n:
            rows.append((name, rname, n))
    with open(os.path.join(raw_dir, name), "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(text)
with open(report, "w") as f:
    f.write("session_file\trule\toccurrences\n")
    for r in rows:
        f.write("%s\t%s\t%d\n" % r)
print("redacted %d files, %d rule hits, counts in %s" % (len(srcs), sum(r[2] for r in rows), report))
PY

# Secret scan by value (T:secret-scan, R11.7). Values are read into memory only; output names files, not values.
python3 -I - "$SECRETS_DIR" "$RAW_DIR" <<'PY'
import os, sys
secrets_dir, raw_dir = sys.argv[1], sys.argv[2]
needles = []  # (label, value)
for dirpath, _, names in os.walk(secrets_dir):
    for n in sorted(names):
        p = os.path.join(dirpath, n)
        data = open(p, "rb").read().decode("utf-8", "replace")
        if n.endswith(".key"):
            for i, line in enumerate(data.splitlines()):
                line = line.strip()
                if len(line) >= 16 and not line.startswith("-----"):
                    needles.append(("%s line %d" % (os.path.relpath(p, secrets_dir), i + 1), line))
        elif n.endswith((".crt", ".srl")):
            continue  # public certificates and the serial file are not secret
        else:
            v = data.strip()
            if len(v) >= 8:
                needles.append((os.path.relpath(p, secrets_dir), v))
hits = 0
for f in sorted(os.listdir(raw_dir)):
    text = open(os.path.join(raw_dir, f), encoding="utf-8", errors="replace").read()
    for label, v in needles:
        if v in text:
            hits += 1
            print("SECRET FOUND: value of secrets/%s appears in ai-logs/raw/%s" % (label, f))
print("secret scan: %d values checked against %d files, %d matches" % (len(needles), len(os.listdir(raw_dir)), hits))
sys.exit(1 if hits else 0)
PY

# Phase map. Sessions are identified by ID; any session not listed is marked for the lead to classify.
python3 -I - "$RAW_DIR" "$OUT_DIR/README.md" <<'PY'
import json, os, sys
raw_dir, out = sys.argv[1], sys.argv[2]
phases = {
    "b2ebea08-4f5e-4379-8f0b-730ca89018db": "P0 requirements and D1-D9, P1 design options, ADRs, version pins, lean plan",
    "38dd8981-353b-45be-9a43-7bc7dc3140b6": "L0 bootstrap and spikes (S1 Garage debugging; redactions R-001)",
    "e73dfe31-c4f5-4462-88b4-bec9dcc42812": "L0 review, L1 replication, L2 failover, L3 backup, L4 restore and PITR (redactions R-002)",
    "d597e1ae-c6c0-481d-b109-4bd17abe23ea": "L5 monitoring and alerting",
    "ef576bb9-39b0-44b0-8766-fdd633c93e79": "L5 completion and L6 security baseline, backup connectivity race",
    "cf5397ce-e4bd-408e-bf16-e7bd63878dde": "L7 clean run and L8 documentation (README, runbooks, AI-process docs, this export script)",
}
rows = []
for f in sorted(os.listdir(raw_dir)):
    sid = f[:-6] if f.endswith(".jsonl") else f
    first = last = ""
    with open(os.path.join(raw_dir, f), encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                ts = json.loads(line).get("timestamp")
            except Exception:
                continue
            if ts:
                first = first or ts
                last = max(last, ts)
    rows.append((first, f, last, phases.get(sid, "UNMAPPED: lead to classify")))
rows.sort()
with open(out, "w") as o:
    o.write("# AI session logs\n\n")
    o.write("Raw Claude Code session transcripts (JSONL), one file per session, exported by `scripts/export-logs.sh` (R11.2).\n\n")
    o.write("They are unedited except for redaction under D5: credentials and personal or cloud identifiers are replaced by visible placeholders such as `[REDACTED-EMAIL]`, `[REDACTED-HOME]`, `[REDACTED-USER]`, `[REDACTED-GCP-PROJECT]`, `[REDACTED-EXTERNAL-IP]` and `[REDACTED:garage-s3-access-key-id]`. ")
    o.write("Counts per rule and file are in [`redactions.tsv`](redactions.tsv); the redaction log is [`../docs/process/redaction-log.md`](../docs/process/redaction-log.md). ")
    o.write("The export fails if any value from `./secrets` appears in the output (secret scan, R11.7).\n\n")
    o.write("Planning and prompt review were done in a separate Claude chat acting as consultant; those chats are not Claude Code sessions and are not in this folder. See [`../docs/ai-process/README.md`](../docs/ai-process/README.md).\n\n")
    o.write("| Session file | First entry (UTC) | Last entry (UTC) | Phase |\n|---|---|---|---|\n")
    for first, f, last, ph in rows:
        o.write("| [`%s`](raw/%s) | %s | %s | %s |\n" % (f, f, first[:19].replace("T", " "), last[:19].replace("T", " "), ph))
print("wrote", out)
PY
echo "Export complete: $RAW_DIR. Review ai-logs/redactions.tsv, then update docs/process/redaction-log.md before committing."
