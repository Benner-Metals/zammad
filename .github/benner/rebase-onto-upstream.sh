#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Rebases the checked-out Benner branch onto the upstream branch that maintains its release
#   line. Conflicts in i18n/zammad.pot are resolved by regenerating the catalog, which needs a
#   working `bundle exec rails`. Any other conflict stops the script: resolve and `git add` the
#   files, then run the copy it names to continue.
#
#   --trial  CI mode: take upstream's catalog instead of regenerating it, abort on other
#            conflicts, and print the outcome as KEY=value lines:
#              trial_result     current, clean, catalog or conflict
#              trial_conflicts  files in conflict at the first conflicting commit (conflict only)
#              trial_dropped    number of Benner commits that became empty, i.e. are upstream
#              trial_dropped_subjects  their original short SHAs and subjects, separated by "; "

# Single-quoted backticks are literal Markdown or shell hints.
# shellcheck disable=SC2016

set -o errexit
set -o nounset
set -o pipefail

mode=local
if [ "${1:-}" = '--trial' ]; then
  mode=trial
fi

script=$(realpath "$0")
cd "$(git rev-parse --show-toplevel)"

# The rebase rewrites the working tree, where this script is absent before its commit, so run
#   from a copy in the git directory; a stopped rebase is continued from there as well.
self="$(git rev-parse --absolute-git-dir)/benner-rebase-onto-upstream.sh"
if [ "$script" != "$self" ]; then
  cp "$script" "$self"
  exec bash "$self" "$@"
fi

# Without replayed rerere resolutions, a stop always shows its conflicts.
git_rebase() {
  GIT_EDITOR=true git -c rerere.enabled=false rebase "$@" > /dev/null 2>&1
}

rebase_dir() {
  local name path
  for name in rebase-merge rebase-apply; do
    path=$(git rev-parse --git-path "$name")
    if [ -d "$path" ]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

stop() {
  local conflicts=$1 message=$2

  if [ "$mode" = trial ]; then
    git rebase --abort
    echo 'trial_result=conflict'
    echo "trial_conflicts=$(echo "$conflicts" | paste -sd ' ' -)"
    exit 0
  fi

  echo "$message" >&2
  exit 1
}

if dir=$(rebase_dir); then
  if [ "$mode" = trial ]; then
    echo 'A rebase is already in progress.' >&2
    exit 1
  fi

  # Continue a rebase that stopped for manual resolution.
  tip=$(cat "${dir}/onto")
  base=$(git merge-base "$(cat "${dir}/orig-head")" "$tip")
  before=$(git log --reverse --format='%h %s' "${base}..$(cat "${dir}/orig-head")")
else
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo 'The working tree has uncommitted changes.' >&2
    exit 1
  fi

  upstream_state=$(.github/benner/upstream-state.sh)
  declare -A state
  while IFS='=' read -r key value; do
    state[$key]=$value
  done <<< "$upstream_state"

  base=${state[upstream_base]}
  tip=${state[upstream_tip]}

  if [ "$base" = "$tip" ]; then
    if [ "$mode" = trial ]; then
      echo 'trial_result=current'
    fi
    echo "Already based on upstream ${state[upstream_tip_build]}." >&2
    exit 0
  fi

  before=$(git log --reverse --format='%h %s' "${base}..HEAD")
  if ! git_rebase --onto "$tip" "$base" && ! rebase_dir > /dev/null; then
    echo "git rebase --onto ${tip} ${base} did not start; run it by hand to see why." >&2
    exit 1
  fi
fi

result=clean
while rebase_dir > /dev/null; do
  conflicts=$(git diff --name-only --diff-filter=U)

  if [ "$conflicts" = 'i18n/zammad.pot' ]; then
    # During a rebase, "ours" is the upstream side.
    git checkout --ours -- i18n/zammad.pot
    if [ "$mode" = local ]; then
      bundle exec rails generate zammad:translation_catalog
    fi
    git add i18n/zammad.pot
    result=catalog
  elif [ -n "$conflicts" ]; then
    stop "$conflicts" "$(printf 'The rebase stopped with conflicts in:\n%s\nResolve and `git add` them, then run `bash %s` to continue.' "$conflicts" "$self")"
  fi

  step=$(git rev-parse HEAD)
  git_rebase --continue || true

  if rebase_dir > /dev/null && [ "$(git rev-parse HEAD)" = "$step" ] && [ -z "$(git diff --name-only --diff-filter=U)" ]; then
    stop '' "The rebase stopped without conflicts; check \`git status\`."
  fi
done

if ! git merge-base --is-ancestor "$tip" HEAD; then
  echo "HEAD is not based on ${tip}; check \`git status\` and \`git reflog\`." >&2
  exit 1
fi

# Commits git dropped because they became empty: match the replayed commits by subject, counting
#   repeated subjects, and report the rest with their original SHAs.
declare -A kept=()
while IFS= read -r subject; do
  n=${kept["$subject"]:-0}
  kept["$subject"]=$((n + 1))
done < <(git log --format=%s "${tip}..HEAD")

dropped=''
while IFS=' ' read -r sha subject; do
  if [ -z "$sha" ]; then
    continue
  fi
  n=${kept["$subject"]:-0}
  if [ "$n" -gt 0 ]; then
    kept["$subject"]=$((n - 1))
  else
    dropped+="${sha} ${subject}"$'\n'
  fi
done <<< "$before"
dropped=${dropped%$'\n'}
after=$(git rev-list --count "${tip}..HEAD")

if [ "$mode" = trial ]; then
  echo "trial_result=${result}"
  echo "trial_dropped=$(grep -c . <<< "$dropped" || true)"
  echo "trial_dropped_subjects=$(paste -sd ';' <<< "$dropped" | sed 's/;/; /g')"
  exit 0
fi

echo "Rebased onto upstream $(git describe --tags "$tip") with ${after} Benner commits."
if [ -n "$dropped" ]; then
  echo 'Dropped as already upstream:'
  while IFS= read -r subject; do
    echo "  ${subject}"
  done <<< "$dropped"
fi
echo 'Next: run .github/benner/specs.sh, then git push --force-with-lease origin HEAD.'
