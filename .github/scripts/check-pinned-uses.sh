#!/usr/bin/env bash
# Verify all external action/workflow refs use full 40-char SHA pins.
# Local actions (uses: ./) and docker:// refs are exempt.
# Expected format: uses: owner/action@<sha> # vX.Y.Z
#   Dependabot reads the inline version comment to track and bump versions.
set -euo pipefail

status=0

while IFS= read -r -d '' file; do
  while IFS= read -r raw; do
    line_no="${raw%%:*}"
    line="${raw#*:}"

    ref="$(printf '%s' "$line" \
      | sed -E "s/^[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]].*$//; s/^['\"]//; s/['\"]$//")"

    case "$ref" in
      ./*|docker://*)
        # Local actions/reusable workflows and docker:// refs are exempt.
        # Dependabot only supports GitHub repository syntax — ignores local refs.
        continue
        ;;
    esac

    if [[ ! "$ref" =~ @[0-9a-f]{40}$ ]]; then
      echo "::error file=$file,line=$line_no::Unpinned or invalid action/workflow ref: $ref"
      status=1
    fi
  done < <(grep -nE '^[[:space:]]*uses:[[:space:]]*[^[:space:]]+@[^[:space:]]+' "$file" || true)
done < <(find .github/workflows .github/actions -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null)

exit $status
