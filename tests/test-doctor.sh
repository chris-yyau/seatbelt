# Tests for doctor.sh
DOCTOR_SCRIPT="$PROJECT_ROOT/scripts/doctor.sh"

test_doctor_outputs_valid_json() {
    EXIT_CODE=0
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null) || EXIT_CODE=$?
    ERRORS=""
    if [ "$EXIT_CODE" -ne 0 ]; then
        ERRORS="\n  doctor.sh exited with $EXIT_CODE"
        fail "doctor outputs valid JSON"
        return
    fi
    # Validate JSON structure
    if ! echo "$STDOUT" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        ERRORS="\n  doctor.sh output is not valid JSON: $STDOUT"
        fail "doctor outputs valid JSON"
        return
    fi
    pass "doctor outputs valid JSON"
}
test_doctor_outputs_valid_json

test_doctor_has_platform() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "import sys, json; d=json.load(sys.stdin); assert 'platform' in d" 2>/dev/null; then
        ERRORS="\n  doctor output missing 'platform' field"
        fail "doctor has platform"
        return
    fi
    pass "doctor has platform"
}
test_doctor_has_platform

test_doctor_has_all_scanners() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    for tool in gitleaks checkov trivy zizmor semgrep; do
        if ! echo "$STDOUT" | python3 -c "import sys, json; d=json.load(sys.stdin); assert '$tool' in d" 2>/dev/null; then
            ERRORS="\n  doctor output missing '$tool' field"
            fail "doctor has all scanners"
            return
        fi
    done
    pass "doctor has all scanners"
}
test_doctor_has_all_scanners

test_doctor_has_package_managers() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "import sys, json; d=json.load(sys.stdin); assert 'package_managers' in d; assert isinstance(d['package_managers'], list)" 2>/dev/null; then
        ERRORS="\n  doctor output missing or invalid 'package_managers' field"
        fail "doctor has package_managers"
        return
    fi
    pass "doctor has package_managers"
}
test_doctor_has_package_managers

test_doctor_scanner_fields() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    # Each scanner entry should have installed, version, path keys
    if ! echo "$STDOUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for tool in ['gitleaks', 'checkov', 'trivy', 'zizmor', 'semgrep']:
    entry = d[tool]
    assert 'installed' in entry, f'{tool} missing installed'
    assert 'version' in entry, f'{tool} missing version'
    assert 'path' in entry, f'{tool} missing path'
    assert isinstance(entry['installed'], bool), f'{tool} installed not bool'
" 2>/dev/null; then
        ERRORS="\n  scanner entries missing required fields (installed/version/path)"
        fail "doctor scanner fields"
        return
    fi
    pass "doctor scanner fields"
}
test_doctor_scanner_fields
