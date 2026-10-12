#!/bin/bash

# SPDX-FileCopyrightText: 2026 Tigerblue77 and the Claude Code Docker container image contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Answers "is the lint of lint-workflows.yml still the one that was decided ?"
#
# The two linters are required checks, and what each of them lets through is a few
# lines of YAML and of command line : a flag, an ignore pattern, a second
# configuration file. A later edit that widens one of them turns the check green on
# something it should have refused, and nothing else in the tree would notice,
# because the check itself would still pass. This is the same kind of record as
# check-ruleset.sh keeps for the ruleset, for a repository with no test suite : the
# decision written down a second time, here, so that changing one copy without the
# other fails a pull request and a reviewer is shown the change.
#
# It is run by each of the two jobs for its own half, so that a red one still says
# which tool it is about :
#
#   actionlint : the command line is exactly the one decided, which keeps the shell
#                and Python integrations off ; the one configuration file,
#                .github/actionlint.yaml, is the only file of its kind and holds
#                exactly the two ignores its header justifies, in the one workflow
#                they are about ;
#   zizmor     : the command line is exactly the one decided, which keeps --offline,
#                for the reason lint-workflows.yml gives, and --strict-collection,
#                without which an unparsable workflow or a dependabot.yml that does
#                not match its schema is a warning and the run is green, zizmor being
#                the only tool that reads dependabot.yml at all ; the one
#                configuration file, .github/zizmor.yml, is the only file of its kind
#                and holds exactly the version-tag policy ; and no workflow and no
#                dependabot.yml carries an inline "zizmor: ignore" comment.
#
# The configuration is compared as written, with comment and blank lines taken out, so
# that the reasons beside it can be edited freely and the settings cannot. A new
# ignore, a lowered threshold or one more setting is a change to the expected text
# below, in the same pull request, which is the point.
#
# Exit 0 : the half asked for is as decided.
# Exit 1 : it is not, and each difference is printed.
# Exit 2 : called wrong.
#
# Usage : .github/check-lint-config.sh actionlint|zizmor [root]

set -euo pipefail

readonly TOOL="${1:-}"
readonly ROOT="${2:-.}"
readonly WORKFLOW="$ROOT/.github/workflows/lint-workflows.yml"

if [ "$TOOL" != "actionlint" ] && [ "$TOOL" != "zizmor" ]; then
  printf 'Usage : %s actionlint|zizmor [root]\n' "${0##*/}" >&2
  exit 2
fi

problems=()

# The lines of a configuration file that are not a comment and not blank
significant() {
  grep -Ev '^[[:space:]]*(#|$)' "$1" || true
}

# A configuration file has exactly the content decided
check_config() {
  local file="$1" expected="$2"
  if [ ! -f "$file" ]; then
    problems+=("$file is missing")
  elif [ "$(significant "$file")" != "$expected" ]; then
    problems+=("$file is not what was decided. Its settings, without comments, are :")
    while IFS= read -r line; do
      problems+=("    $line")
    done < <(significant "$file")
  fi
}

# The tool's configuration file is the only one of its kind : a second one, under
# another extension or in the other place the tool looks, would be read as well
check_only_file() {
  local expected="$1" pattern="$2" found
  found="$(find "$ROOT" "$ROOT/.github" -maxdepth 1 -type f -name "$pattern" | sort | tr '\n' ' ')"
  if [ "$found" != "$expected " ]; then
    problems+=("expected $expected as the only configuration file, found : ${found:-none}")
  fi
}

# The tool is run by exactly one line of the workflow, and it is the decided one
check_command() {
  local marker="$1" expected="$2" count
  count="$(grep -c -- "$marker" "$WORKFLOW" || true)"
  if [ "$count" != "1" ] || ! grep -Fxq -- "$expected" "$WORKFLOW"; then
    problems+=("$WORKFLOW does not run $TOOL with exactly : ${expected#*run: }")
  fi
}

if [ "$TOOL" = "actionlint" ]; then
  IFS= read -r command << 'EOF'
        run: '"$(go env GOPATH)/bin/actionlint" -shellcheck= -pyflakes='
EOF
  check_command 'bin/actionlint"' "$command"

  check_only_file "$ROOT/.github/actionlint.yaml" 'actionlint.y*ml'

  expected="$(cat << 'EOF'
paths:
  .github/workflows/auto_update_pull_request_branches.yml:
    ignore:
      - 'missing input "app-id" which is required by action "actions/create-github-app-token@v3"'
      - 'input "client-id" is not defined in action "actions/create-github-app-token@v3"'
EOF
  )"
  check_config "$ROOT/.github/actionlint.yaml" "$expected"
fi

if [ "$TOOL" = "zizmor" ]; then
  IFS= read -r command << 'EOF'
        run: '"$RUNNER_TEMP/zizmor/bin/zizmor" --offline --strict-collection --format github .'
EOF
  check_command 'bin/zizmor"' "$command"

  check_only_file "$ROOT/.github/zizmor.yml" 'zizmor.y*ml'

  expected="$(cat << 'EOF'
rules:
  unpinned-uses:
    config:
      policies:
        "*": ref-pin
EOF
  )"
  check_config "$ROOT/.github/zizmor.yml" "$expected"

  ignores="$(grep -rnE 'zizmor:[[:space:]]*ignore' "$ROOT/.github/workflows" "$ROOT/.github/dependabot.yml" || true)"
  if [ -n "$ignores" ]; then
    problems+=("an inline zizmor ignore comment exists, and none is allowed :")
    while IFS= read -r line; do
      problems+=("    $line")
    done <<< "$ignores"
  fi
fi

if [ "${#problems[@]}" -gt 0 ]; then
  echo "The $TOOL lint is no longer configured as it was decided :"
  printf '  - %s\n' "${problems[@]}"
  echo
  echo "If the change is deliberate, change the expected text in .github/check-lint-config.sh"
  echo "in the same pull request, and say why in the description."
  exit 1
fi

echo "The $TOOL lint is configured as decided."
