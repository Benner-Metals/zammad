#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Prints the image tags of HEAD as KEY=value lines:
#
#   existing_tags  every <upstream build>-bm<N> already reserved for HEAD, space-separated
#   next_tag      the next unused <upstream build>-bm<N>, e.g. 7.2.0-0021-bm1
#
# N counts the Benner builds on the same upstream build. reserve-tag.sh records every number
#   as the git tag benner/<image tag> before its image is pushed, so numbers are never reused.
#
# Usage: image-tag.sh <upstream build>

set -o errexit
set -o nounset
set -o pipefail

prefix="$1-bm"

number() {
  local n=${1#"benner/${prefix}"}
  if [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "$n"
  fi
}

existing=()
while read -r tag; do
  if [ -n "$(number "$tag")" ]; then
    existing+=("${tag#benner/}")
  fi
done < <(git tag --points-at HEAD --list "benner/${prefix}*")

last=0
while read -r tag; do
  n=$(number "$tag")
  if [ -n "$n" ] && [ "$n" -gt "$last" ]; then
    last=$n
  fi
done < <(git tag --list "benner/${prefix}*")

echo "existing_tags=${existing[*]}"
echo "next_tag=${prefix}$((last + 1))"
