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
assert 'active' in h, 'missing active'
assert 'total' in h, 'missing total'
assert 'score' in h, 'missing score'
assert h['total'] == 6, f'total should be 6, got {h[\"total\"]}'
assert isinstance(h['active'], int), 'active not int'
assert h['score'] == f\"{h['active']}/6\", 'score format wrong'
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

# ── install_cmd field per scanner ───────────────────────────────────
test_doctor_has_install_cmd() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for tool in ['gitleaks', 'checkov', 'trivy', 'zizmor', 'semgrep', 'shellcheck']:
    entry = d[tool]
    assert 'install_cmd' in entry, f'{tool} missing install_cmd'
    if entry['installed']:
        assert entry['install_cmd'] is None, f'{tool} installed but install_cmd not null'
" 2>/dev/null; then
        ERRORS="\n  scanner entries missing or invalid 'install_cmd' field"
        fail "doctor has install_cmd"
        return
    fi
    pass "doctor has install_cmd"
}
test_doctor_has_install_cmd

test_doctor_install_cmd_priority() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for tool in ['gitleaks', 'checkov', 'trivy', 'zizmor', 'semgrep', 'shellcheck']:
    entry = d[tool]
    if not entry['installed']:
        assert entry['install_cmd'] is not None, f'{tool} not installed but no install_cmd'
        assert isinstance(entry['install_cmd'], str), f'{tool} install_cmd not string'
        assert len(entry['install_cmd']) > 0, f'{tool} install_cmd is empty'
" 2>/dev/null; then
        ERRORS="\n  install_cmd not provided for missing tools"
        fail "doctor install_cmd priority"
        return
    fi
    pass "doctor install_cmd priority"
}
test_doctor_install_cmd_priority

# ── install_cmd selection logic (brew-free environment) ─────────────
# Verifies that each tool produces a recognized install command when
# run without brew — exercises the package manager priority table.
test_doctor_install_cmd_selection() {
    local tmpbin
    tmpbin=$(make_degraded_path)
    # Add pip3, cargo, go, apt-get but NOT brew to exercise fallback paths
    for cmd in pip3 cargo go apt-get; do
        local p
        p=$(command -v "$cmd" 2>/dev/null || true)
        [ -n "$p" ] && ln -sf "$p" "$tmpbin/$cmd"
    done

    STDOUT=$(PATH="$tmpbin" bash "$DOCTOR_SCRIPT" 2>/dev/null)
    rm -rf "$tmpbin"
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "
import sys, json, shutil
d = json.load(sys.stdin)
# Known-good prefixes for each tool when brew is absent
expected = {
    'gitleaks': ('go install',) if shutil.which('go') else ('https://',),
    'checkov':  ('pip3',) if shutil.which('pip3') else ('https://',),
    'trivy':    ('https://',),  # apt-get requires external repo — always link to install docs
    'zizmor':   ('pip3',) if shutil.which('pip3') else (('cargo',) if shutil.which('cargo') else ('https://',)),
    'semgrep':  ('pip3',) if shutil.which('pip3') else ('https://',),
    'shellcheck': ('sudo apt-get',) if shutil.which('apt-get') else ('https://',),
}
for tool, prefixes in expected.items():
    cmd = d[tool].get('install_cmd')
    if cmd is None:
        continue  # tool is installed; skip
    assert any(cmd.startswith(p) for p in prefixes), \
        f'{tool} install_cmd {cmd!r} does not start with any of {prefixes}'
" 2>/dev/null; then
        ERRORS="\n  install_cmd selection returned unexpected command for one or more tools"
        fail "doctor install_cmd selection"
        return
    fi
    pass "doctor install_cmd selection"
}
test_doctor_install_cmd_selection

# ── Health score is computed correctly (regression: field-order independence) ──
test_doctor_health_score_correct() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
h = d['health']
# Recompute expected active count from scanner entries
expected = 0
for tool in ['gitleaks', 'checkov', 'zizmor', 'semgrep', 'shellcheck']:
    if d[tool].get('installed', False):
        expected += 1
trivy = d['trivy']
if trivy.get('installed', False) and trivy.get('db_cached', False):
    expected += 1
assert h['active'] == expected, f'health active={h[\"active\"]} but computed={expected}'
assert h['score'] == f'{expected}/6', f'score mismatch'
" 2>/dev/null; then
        ERRORS="\n  health score does not match recomputed value"
        fail "doctor health score correct"
        return
    fi
    pass "doctor health score correct"
}
test_doctor_health_score_correct

test_doctor_has_advisory() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
a = d['advisory']
assert 'commitlint' in a, 'missing commitlint'
assert 'signing' in a, 'missing signing'
assert isinstance(a['signing']['gpgsign_configured'], bool), 'gpgsign_configured not bool'
" 2>/dev/null; then
        ERRORS="\n  doctor output missing or invalid 'advisory' field"
        fail "doctor has advisory section"
        return
    fi
    pass "doctor has advisory section"
}
test_doctor_has_advisory
