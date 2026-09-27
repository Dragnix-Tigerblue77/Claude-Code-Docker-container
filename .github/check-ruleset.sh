#!/bin/bash

# SPDX-FileCopyrightText: 2026 Tigerblue77 and the Claude Code Docker container image contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Answers "does .github/rulesets/main.json still describe a gate that can pass ?"
#
# That file is the list of checks "gh pr merge --auto" waits for before it merges
# one of Dependabot's updates, in the form GitHub's "Import a ruleset" takes. A
# required check is matched by a job's display name -- never its key, never the
# workflow's name -- so renaming a job without editing the file leaves a context
# nothing ever reports, and every pull request then waits for it for ever with
# no error to read. wader/postfix-relay, which this repository is aligned on,
# keeps its own copy true with tests/test_ruleset.py ; this is the same two
# checks for a repository with no test suite.
#
# Two things are checked :
#   - every required context is the name of a job in a workflow a pull request
#     starts. A job without a "name:" reports under its key, so the key is used ;
#   - the file still gates the default branch : enforced, aimed at
#     ~DEFAULT_BRANCH with nothing excluded, no bypass actor, exactly one rule
#     that requires checks, and no required approval. A re-export made after
#     clicking around the settings page can bring any of those back while still
#     parsing.
#
# The file is the whole of the live ruleset, not only its checks : main is also
# protected against deletion and force-pushes, takes pull requests only and
# keeps a linear history, and a file carrying the checks alone would drop all
# four the day it was imported in place of the live one. Those four are not
# asserted -- they are protections, not what makes the gate pass or fail. The
# approval count is : one required approval holds every Dependabot update for a
# person, however green.
#
# The workflows are read with awk rather than a YAML parser, which nothing here
# installs. Every workflow in this repository is written in the one shape it
# reads -- two-space job keys under a top-level "jobs:", their "name:" four
# spaces in -- and a job it cannot see is reported missing, so the shortcut
# fails red rather than green.

set -euo pipefail

readonly ROOT="${1:-.}"
readonly RULESET="$ROOT/.github/rulesets/main.json"
readonly WORKFLOWS="$ROOT/.github/workflows"

problems=()

check() {
  local expected="$1" actual="$2" what="$3"
  if [ "$actual" != "$expected" ]; then
    problems+=("$what : expected $expected, found $actual")
  fi
}

check '"branch"' "$(jq -c '.target' "$RULESET")" "target"
check '"active"' "$(jq -c '.enforcement' "$RULESET")" "enforcement"
check '["~DEFAULT_BRANCH"]' "$(jq -c '.conditions.ref_name.include' "$RULESET")" "the branches it applies to"
check '[]' "$(jq -c '.conditions.ref_name.exclude' "$RULESET")" "the branches it excludes"
check '[]' "$(jq -c '.bypass_actors' "$RULESET")" "bypass actors"
check '1' "$(jq '[.rules[] | select(.type == "required_status_checks")] | length' "$RULESET")" "the rules that require checks"
check '0' "$(jq '[.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count] | add // 0' "$RULESET")" "the approvals a merge requires"

reported=""
for workflow in "$WORKFLOWS"/*.yml; do
  grep -Eq '^on: pull_request$|^  pull_request:' "$workflow" || continue
  reported+=$(awk '
    /^jobs:/ { in_jobs = 1; next }
    in_jobs && /^[^ #]/ { in_jobs = 0 }
    !in_jobs { next }
    /^  [A-Za-z0-9_-]+:[ ]*$/ {
      if (key != "" && !named) print key
      key = $1; sub(/:$/, "", key); named = 0; next
    }
    key != "" && !named && /^    name:/ {
      line = $0; sub(/^    name:[ ]*/, "", line); gsub(/^"|"$/, "", line)
      print line; named = 1
    }
    END { if (key != "" && !named) print key }
  ' "$workflow")
  reported+=$'\n'
done

contexts=0
while IFS= read -r context; do
  [ -n "$context" ] || continue
  contexts=$((contexts + 1))
  if ! grep -Fxq -- "$context" <<< "$reported"; then
    problems+=("required context \"$context\" names no job a pull request runs, so it can never report")
  fi
done < <(jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context' "$RULESET")

if [ "$contexts" -eq 0 ]; then
  problems+=("no check is required at all, which would let auto-merge land an update with nothing checked")
fi

if [ "${#problems[@]}" -gt 0 ]; then
  echo "$RULESET no longer describes a gate that can pass :"
  printf '  - %s\n' "${problems[@]}"
  echo
  echo "Job names a pull request reports :"
  grep -v '^$' <<< "$reported" | sed 's/^/  /'
  exit 1
fi

echo "$contexts required check(s), each reported by a job a pull request runs."
