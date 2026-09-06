#!/bin/bash

# SPDX-FileCopyrightText: 2026 Tigerblue77 and the Claude Code Docker container image contributors
# SPDX-License-Identifier: AGPL-3.0-only

# SessionStart hook for Claude Code on the web.
#
# It installs nothing, which is what makes it different from the one in
# tigerblue77/dell_idrac_fan_controller_docker that it is modelled on. Nothing here is gated
# on a tool a hook could apt-install : the one thing a session needs beyond git is a Docker
# daemon, which is not a package. What this configures instead is the one rule a session
# cannot satisfy by remembering it.
#
# THE RULE. CONTRIBUTING.md requires a Signed-off-by on every commit, and the Sign-off
# workflow now refuses a pull request without one. For a commit a session authored, the
# trailer has to name the MAINTAINER : a tool cannot make a first-person certification, and
# a trailer naming one satisfies a checker while naming nobody who could state it.
#
# WHY AN ALIAS AND NOT A HABIT. "git commit -s" DERIVES the trailer from the author, so on a
# commit authored under the agent it writes exactly the shape the check refuses. The correct
# form has to be passed explicitly, every time, and CONTRIBUTING.md says what that costs :
#
#     a rule that has to be remembered every time is a rule that gets forgotten :
#     automate it in the session rather than trusting it to memory
#
# That sentence has been in CONTRIBUTING.md since the legal annexes landed, pointing at an
# automation that did not exist. Measured while it did not : four of the five commits on main
# carried no sign-off at all. This file is that automation.
#
# "git signoff" therefore replaces "git commit -s" for a session working here. It takes the
# same arguments -- "git signoff -m ...", "git signoff --amend --no-edit" -- and differs only
# in whose name ends up on the trailer.
#
# It is best-effort and never blocks a session : every failure below is reported and returns
# 0. A session that cannot set an alias should still be able to work ; it just has to pass
# --trailer by hand, which is what the message tells it.

set -uo pipefail

# Local checkouts are the developer's own machine, with their own git configuration and their
# own idea of which aliases should exist on it. This hook is for the ephemeral remote
# container, where the alternative to configuring is nothing at all.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

readonly SIGN_OFF_NAME="Tigerblue77"
readonly SIGN_OFF_EMAIL="37409593+tigerblue77@users.noreply.github.com"

readonly REPO="${CLAUDE_PROJECT_DIR:-.}"

if ! git -C "$REPO" rev-parse --git-dir > /dev/null 2>&1; then
  echo "session-start : ${REPO} is not a git repository, so the sign-off alias was not set"
  exit 0
fi

# Repository-local on purpose, not --global : this trailer is this project's convention, and
# a session that later works in another checkout inside the same container must not inherit
# a "git signoff" that quietly certifies under a name that repository never asked for.
if git -C "$REPO" config alias.signoff \
  "commit --trailer \"Signed-off-by: ${SIGN_OFF_NAME} <${SIGN_OFF_EMAIL}>\""; then
  echo "session-start : \"git signoff\" now commits with Signed-off-by: ${SIGN_OFF_NAME} <${SIGN_OFF_EMAIL}>."
  echo "session-start : use it instead of \"git commit -s\", which would derive the trailer from the author."
else
  echo "session-start : could not set the sign-off alias, so commits made here must pass the trailer by hand:"
  echo "session-start :   git commit --trailer \"Signed-off-by: ${SIGN_OFF_NAME} <${SIGN_OFF_EMAIL}>\""
fi

exit 0
