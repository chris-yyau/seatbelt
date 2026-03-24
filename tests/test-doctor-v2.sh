# Tests for doctor.sh v2 enhancements
DOCTOR_SCRIPT="$PROJECT_ROOT/scripts/doctor.sh"

# ── Health score field ──────────────────────────────────────────────
test_doctor_has_health_score() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
h = d['health']
assert 'installed' in h, 'missing installed'
assert 'total' in h, 'missing total'
assert 'score' in h, 'missing score'
assert h['total'] == 4, f'total should be 4, got {h[\"total\"]}'
assert isinstance(h['installed'], int), 'installed not int'
assert h['score'] == f\"{h['installed']}/4\", 'score format wrong'
" 2>/dev/null; then
        ERRORS="\n  doctor output missing or invalid 'health' field"
        fail "doctor has health score"
        return
    fi
    pass "doctor has health score"
}
test_doctor_has_health_score

# ── Trivy DB cached field ───────────────────────────────────────────
test_doctor_trivy_db_cached() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
trivy = d['trivy']
assert 'db_cached' in trivy, 'missing db_cached'
assert isinstance(trivy['db_cached'], bool), 'db_cached not bool'
" 2>/dev/null; then
        ERRORS="\n  trivy entry missing 'db_cached' field"
        fail "doctor trivy db_cached"
        return
    fi
    pass "doctor trivy db_cached"
}
test_doctor_trivy_db_cached
