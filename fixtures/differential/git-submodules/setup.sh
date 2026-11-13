#!/usr/bin/env bash
# Pre-seed for fixtures/differential/git-submodules.
#
# script/differential's git-init manifest materializes each listed directory as
# a real git repo, but a nested .git directory cannot be committed, so the
# embedded submodule repo inside subgem is generated here instead:
#   extra/subrepos/subgem/subdep/.git      -> gitdir pointer file
#   extra/subrepos/subgem/.subdep-git/     -> the real git store
# Both paths are gitignored. The store commit uses the same pinned
# author/committer env as script/differential, so its HEAD equals the SHA the
# harness will compute for extra/subrepos/subdep (verified below).
#
# Run once before `script/differential`:
#   bash fixtures/differential/git-submodules/setup.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
fix="$here/extra/subrepos"

PINENV=(
  GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.test
  GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.test
  GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
)

subgem="$fix/subgem"
rm -rf "$subgem/.subdep-git" "$subgem/subdep/.git"
mkdir -p "$subgem/subdep/lib"
cp "$fix/subdep/subdep.gemspec" "$subgem/subdep/"
cp "$fix/subdep/lib/subdep.rb" "$subgem/subdep/lib/"

env "${PINENV[@]}" git -C "$subgem/subdep" -c core.autocrlf=false -c commit.gpgsign=false init -q -b master
git -C "$subgem/subdep" -c core.autocrlf=false add -A
env "${PINENV[@]}" git -C "$subgem/subdep" -c commit.gpgsign=false commit -q -m init
S=$(git -C "$subgem/subdep" rev-parse HEAD)

mv "$subgem/subdep/.git" "$subgem/.subdep-git"
printf 'gitdir: ../.subdep-git\n' > "$subgem/subdep/.git"

# Verify the embedded HEAD equals what the harness staging would compute for
# extra/subrepos/subdep with the same content and pinned env.
chk="$(mktemp -d)"
cp -r "$fix/subdep/." "$chk/"
env "${PINENV[@]}" git -C "$chk" -c core.autocrlf=false -c commit.gpgsign=false init -q -b master
git -C "$chk" -c core.autocrlf=false add -A
env "${PINENV[@]}" git -C "$chk" -c commit.gpgsign=false commit -q -m init
S2=$(git -C "$chk" rev-parse HEAD)
rm -rf "$chk"

if [ "$S" != "$S2" ]; then
  echo "setup.sh: embedded HEAD $S != harness-staged HEAD $S2" >&2
  exit 1
fi

echo "git-submodules fixture pre-seeded: subdep HEAD=$S"
