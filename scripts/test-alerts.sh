#!/usr/bin/env bash
# L5 (R10.2): checks and unit-tests the alert rules with promtool from the pinned Prometheus image. Needs Docker
# only, no cluster. Steps:
#   1. promtool check rules on the real rule file;
#   2. every rule has a severity label and summary and why annotations;
#   3. every alert has at least one test that expects it to fire and one that expects silence;
#   4. promtool test rules against a copy of the rules without annotations (the tests check labels and timing).
# Writes docs/evidence/L5/alert-rules.md.
. "$(dirname "$0")/spikes/lib.sh"
RULES="$ROOT_DIR/deploy/monitoring/rules/pg-ha.rules.yml"; TESTS="$ROOT_DIR/tests/alerts/pg-ha.test.yml"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp "$TESTS" "$W/pg-ha.test.yml"
python3 -I - "$RULES" "$W/pg-ha.rules.yml" <<'EOF'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for g in doc["groups"]:
    for r in g["rules"]:
        r.pop("annotations", None)
yaml.safe_dump(doc, open(sys.argv[2], "w"), sort_keys=False)
EOF
promtool() { docker run --rm --network none -u "$(id -u):$(id -g)" -v "$1:/w:ro" -w /w --entrypoint promtool "$PROMETHEUS_IMAGE" "${@:2}"; }

BODY=$(mktemp); CHECKS=$(mktemp); FAILS=0; T0=$SECONDS; STARTED=$(date -u +%FT%TZ)
cp "$RULES" "$W/orig.rules.yml"
section "promtool check rules"
run "promtool '$W' check rules orig.rules.yml" && rc=0 || rc=$?
check "promtool check rules passes on deploy/monitoring/rules/pg-ha.rules.yml" test "$rc" = 0

section "Rule metadata and test coverage"
cov=$(python3 -I - "$RULES" "$TESTS" <<'EOF'
import sys, yaml
rules = [r for g in yaml.safe_load(open(sys.argv[1]))["groups"] for r in g["rules"]]
tests = yaml.safe_load(open(sys.argv[2]))["tests"]
fires, silent = set(), set()
for t in tests:
    for a in t.get("alert_rule_test", []):
        (fires if a.get("exp_alerts") else silent).add(a["alertname"])
bad = 0
print("| Alert | Severity | Summary | Why | Fires test | Silent test |\n|---|---|---|---|---|---|")
for r in rules:
    n = r["alert"]; sev = r.get("labels", {}).get("severity", ""); ann = r.get("annotations", {})
    row = [n, sev or "MISSING", "yes" if ann.get("summary") else "MISSING", "yes" if ann.get("why") else "MISSING",
           "yes" if n in fires else "MISSING", "yes" if n in silent else "MISSING"]
    bad += row.count("MISSING")
    print("| " + " | ".join(row) + " |")
names = {r["alert"] for r in rules}
print(f"\n{len(rules)} rules, {len(names)} distinct alert names, {len(tests)} test groups.")
sys.exit(1 if bad else 0)
EOF
) && rc=0 || rc=$?
printf '\n%s\n' "$cov" >> "$BODY"; printf '%s\n' "$cov"
check "Every rule has severity, summary and why; every alert has a firing and a silent test" test "$rc" = 0
scoped=$(python3 -I - "$RULES" <<'EOF'
import sys, yaml
platform = {"DiskLow", "CoreDNSNotReady", "MonitoringTargetDown"}
for g in yaml.safe_load(open(sys.argv[1]))["groups"]:
    for r in g["rules"]:
        if r["alert"] not in platform and 'namespace="pg-ha"' not in r["expr"]:
            print(r["alert"])
EOF
)
check "Every Postgres, backup and restore rule selects namespace=\"pg-ha\" (unscoped: ${scoped:-none})" test -z "$scoped"

section "promtool test rules"
TAIL=80 run "promtool '$W' test rules pg-ha.test.yml" && rc=0 || rc=$?
check "promtool test rules passes (tests/alerts/pg-ha.test.yml)" test "$rc" = 0

mkdir -p "$EV_DIR/L5"
verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
{ printf '# L5: alert rule unit tests (R10.2)\n\n**Result: %s**\n\n' "$verdict"
  printf -- '- **What:** `promtool check rules` and `promtool test rules` from the pinned Prometheus image, plus checks that every rule has a severity, a summary and a reason for its threshold, and that every alert has a test where it fires and one where it stays silent. The tests run against a copy of the rules without annotations, so they check labels and timing. No cluster is needed.\n'
  printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make test-alerts`\n' "$STARTED" "$((SECONDS-T0))"
  printf -- '- **Versions:** promtool from `%s`\n' "$PROMETHEUS_IMAGE"
  printf '\n## Checks\n\n| Check | Result |\n|---|---|\n'; cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_DIR/L5/alert-rules.md"
rm -f "$BODY" "$CHECKS"
[ ! -x "$ROOT_DIR/tests/l5-summary.sh" ] || "$ROOT_DIR/tests/l5-summary.sh"
log "RESULT L5 alert-rules: $verdict -> docs/evidence/L5/alert-rules.md"
[ "$FAILS" -eq 0 ]
