#!/usr/bin/env bash
# Tells CI whether an event changed anything the build jobs depend on. Documentation (Markdown at
# the repository root, anything under .agents/) and the TestFlight workflow, which no CI job uses,
# don't count. Prints code=false when every changed path is one of those, else code=true.
# ci.yml and these scripts count: they change CI itself. Any failure, an unknown event or a list
# that may be incomplete prints code=true, so CI runs in full when in doubt; this script always
# exits 0.
#
# Reads GITHUB_EVENT_NAME and GITHUB_REPOSITORY, and for a pull request PR_NUMBER and
# PR_CHANGED_FILES, for a push BEFORE and AFTER. Needs gh with a token that can read the repository.
set -uo pipefail

run_all() {
  echo "code=true"
  exit 0
}

# One line per changed file: its path, and a renamed file's old path, so moving code into .agents/
# still counts as a code change.
JQ_FILE='[.filename, (.previous_filename // empty)] | join("\n")'

case "${GITHUB_EVENT_NAME:-}" in
  pull_request)
    list=$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/files" \
      --jq ".[] | $JQ_FILE | @json") || run_all
    # The files API stops at 3000 files: fewer than the pull request has means a partial list.
    expected=${PR_CHANGED_FILES:-}
    ;;
  push)
    [[ "${BEFORE:-}" =~ ^0*$ ]] && run_all
    list=$(gh api "repos/$GITHUB_REPOSITORY/compare/$BEFORE...$AFTER" \
      --jq ".files[] | $JQ_FILE | @json") || run_all
    expected=
    ;;
  *)
    run_all
    ;;
esac

[ -n "$list" ] || run_all
count=$(grep -c '' <<< "$list")
if [ -n "$expected" ]; then
  [ "$count" -eq "$expected" ] || run_all
else
  # The compare API lists at most 300 files.
  [ "$count" -lt 300 ] || run_all
fi

while IFS= read -r path; do
  case "$path" in
    .agents/*) ;;
    .github/workflows/testflight.yml) ;;
    */*) run_all ;;
    *.md) ;;
    *) run_all ;;
  esac
done < <(jq -r '.' <<< "$list")

echo "code=false"
