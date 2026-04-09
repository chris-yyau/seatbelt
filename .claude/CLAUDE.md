# Seatbelt Plugin

## Version Sync

Version numbers are managed across two manifests (declared in `.version-bump.json`):

- `package.json` — `version` field
- `.claude-plugin/plugin.json` — `version` field

Note: `.claude-plugin/marketplace.json` has a separate `metadata.version` field that tracks the scanner-standard version independently.

**Automated (preferred):** semantic-release bumps all manifests via `@semantic-release/exec` → `bump-version.sh` on every merge to main. No manual version management needed.

**Drift detection:** `./scripts/bump-version.sh --check` runs in CI on PRs to catch version desync.
