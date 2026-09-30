#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Prints the upstream state of the checked-out Benner branch as KEY=value lines,
# suitable for appending to $GITHUB_OUTPUT:
#
#   release_line         Zammad release line of the branch, e.g. 7.2
#   upstream_branch      upstream branch maintaining that line: stable-<line> once upstream has
#                        moved on to a newer release, otherwise stable
#   upstream_base        upstream commit the branch is built on
#   upstream_base_build  its upstream build, e.g. 7.2.0-0021 (an official image tag while the
#                        line is on stable)
#   upstream_tip         current tip of upstream_branch
#   upstream_tip_build   its upstream build
#   stable_tip_build     upstream build of upstream stable, which may be a newer line
#   benner_commits       space-separated Benner commits on top of upstream_base

set -o errexit
set -o nounset
set -o pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/zammad/zammad.git}

line=$(cut -d. -f1-2 VERSION)
branch=stable
if git ls-remote --exit-code --heads "$UPSTREAM_URL" "stable-${line}" > /dev/null; then
  branch="stable-${line}"
fi

git fetch --quiet --no-tags "$UPSTREAM_URL" \
  "+refs/heads/${branch}:refs/remotes/upstream/${branch}" \
  '+refs/heads/stable:refs/remotes/upstream/stable' \
  '+refs/tags/*:refs/tags/*'

# Same formula as zammad/zammad's docker-release workflow, which tags the official image of
#   each stable commit this way (git describe 7.2.0-21-g31b3d8d6a3 -> 7.2.0-0021).
upstream_build() {
  git describe --tags --long "$1" | awk -F'-' '{printf "%s-%04d\n", $1, $(NF-1)}'
}

base=$(git merge-base HEAD "refs/remotes/upstream/${branch}")
tip=$(git rev-parse "refs/remotes/upstream/${branch}")

echo "release_line=${line}"
echo "upstream_branch=${branch}"
echo "upstream_base=${base}"
echo "upstream_base_build=$(upstream_build "$base")"
echo "upstream_tip=${tip}"
echo "upstream_tip_build=$(upstream_build "$tip")"
echo "stable_tip_build=$(upstream_build refs/remotes/upstream/stable)"
echo "benner_commits=$(git rev-list --reverse "${base}..HEAD" | paste -sd ' ' -)"
