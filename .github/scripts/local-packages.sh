#!/usr/bin/env bash
# The Xcode project references some Swift packages by local path
# (XCLocalSwiftPackageReference). Package.resolved doesn't record them, so
# .github/local-packages.txt pins each one to a commit of its repository.
#
#   local-packages.sh checkout   clone each pinned commit into its path (CI)
#   local-packages.sh pin        rewrite the pins from the local checkouts
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PBXPROJ="$ROOT/YetAnotherEBookReader.xcodeproj/project.pbxproj"
PINS="$ROOT/.github/local-packages.txt"

# The paths of the project's local packages, as the project writes them.
project_paths() {
  awk '/Begin XCLocalSwiftPackageReference section/,/End XCLocalSwiftPackageReference section/' "$PBXPROJ" |
    sed -n 's/^[[:space:]]*relativePath = "\{0,1\}\([^";]*\)"\{0,1\};$/\1/p' |
    sort -u
}

# A relative path is relative to the directory holding the .xcodeproj.
resolve() {
  case $1 in
    /*) echo "$1" ;;
    *) echo "$ROOT/$1" ;;
  esac
}

# The pins as "path repository commit branch" lines, comments dropped.
pins() {
  grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$PINS"
}

checkout() {
  local missing=0 path url commit dir parent
  while read -r path; do
    if ! pins | awk -v p="$path" '$1 == p { found = 1 } END { exit !found }'; then
      echo "error: the project references $path, which has no pin in ${PINS#"$ROOT"/}" >&2
      missing=1
    fi
  done < <(project_paths)
  [ "$missing" -eq 0 ] || exit 1

  while read -r path url commit _; do
    dir=$(resolve "$path")
    if [ -e "$dir" ]; then
      if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ]; then
        echo "$dir is already at $commit"
        continue
      fi
      echo "error: $dir exists and isn't at the pinned $commit; leaving it alone" >&2
      exit 1
    fi

    # On a CI runner the developer's home doesn't exist and /Users is root's.
    parent=$(dirname "$dir")
    mkdir -p "$parent" 2>/dev/null || sudo mkdir -p "$parent"
    [ -w "$parent" ] || sudo chown "$(id -u):$(id -g)" "$parent"

    echo "Cloning $url at $commit into $dir"
    git init --quiet "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch --quiet --depth 1 origin "$commit"
    git -C "$dir" checkout --quiet --detach FETCH_HEAD
  done < <(pins)
}

pin() {
  local path dir url commit branch tmp
  tmp=$(mktemp)
  sed -n '/^#/p' "$PINS" > "$tmp"

  while read -r path; do
    dir=$(resolve "$path")
    commit=$(git -C "$dir" rev-parse HEAD)
    url=$(git -C "$dir" remote get-url origin | sed -E 's#^git@github\.com:#https://github.com/#')
    branch=$(git -C "$dir" branch --show-current)

    if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
      echo "warning: $dir has uncommitted changes, which CI won't see" >&2
    fi
    git -C "$dir" fetch --quiet origin
    if [ -z "$(git -C "$dir" branch -r --contains "$commit" --list 'origin/*')" ]; then
      echo "warning: $commit isn't on any branch of origin; push it so CI can fetch it" >&2
    fi

    echo "$path $url $commit ${branch:--}" >> "$tmp"
  done < <(project_paths)

  mv "$tmp" "$PINS"
  git -C "$ROOT" --no-pager diff --stat -- "$PINS"
}

case ${1:-} in
  checkout) checkout ;;
  pin) pin ;;
  *)
    echo "usage: $0 checkout|pin" >&2
    exit 2
    ;;
esac
