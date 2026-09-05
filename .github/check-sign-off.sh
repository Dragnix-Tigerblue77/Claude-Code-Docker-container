#!/bin/bash

# SPDX-FileCopyrightText: 2026 Tigerblue77 and the Claude Code Docker container image contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Answers "does every commit this pull request adds carry a Signed-off-by ?",
# which is the question nothing in this repository asked until now.
#
# CONTRIBUTING.md states the rule -- "Every commit must carry a Signed-off-by
# line" -- and it is not decoration here. This project is dual-licensed,
# AGPL-3.0-only in LICENSE plus LICENSE-COMMERCIAL.md, and the sign-off is the
# record that a contributor had the right to submit their work under both arms.
# It is what makes the commercial half grantable.
#
# Measured when this file was written, one of the five commits on main carried
# it. A rule stated in one file, honoured a fifth of the time and checked
# nowhere is worse than no rule at all : nobody goes looking for what is
# already supposed to be required.
#
# ON PULL REQUESTS ONLY, AND THAT IS NOT A GAP. A squash merge composes its
# message from the pull request rather than from the branch, so the branch's own
# commits are the last place the trailer still exists to be read -- by the time
# main has the squash, the information is gone. Running this on a push to main
# would also mean a permanently red default branch, since the four unsigned
# commits already there cannot be signed without rewriting published history.
#
# So it gates what arrives from here on, and leaves the history it was written
# for alone.
#
# WHAT IT DECIDES ABOUT WHOSE NAME IS ON THE TRAILER, AND WHAT IT CANNOT. The
# DCO is a first-person certification -- "I certify that..." -- and no tool can
# tell a person from an identity configured in git config. One half of it is
# decidable and is checked below : a trailer naming the AGENT certifies nobody,
# because a tool cannot make the statement. CONTRIBUTING.md says so directly,
# under "Contributions written by an agent" : the agent is credited in the
# author field or in a Co-Authored-By trailer, and the sign-off is the
# maintainer's, whose act of reviewing and merging is the certification.
#
# The other half is not decidable and no amount of trying would make it so. A
# commit signed by the maintainer that a session actually wrote is
# indistinguishable from one they typed. That is the maintainer's to hold, not
# a workflow's, and this script does not pretend otherwise.
#
# MERGE COMMITS ARE SKIPPED. Merging main into a branch to resolve a conflict is
# the correct thing to do, and git writes that commit itself with no sign-off.
# Failing a pull request for it would punish the contributor who resolved their
# conflict properly, and the merge carries no contribution of its own to
# certify -- everything it brings in was already signed where it was authored.
#
# Exit 0 : every commit in the range carries a well-formed sign-off.
# Exit 1 : at least one does not, or one certifies under the agent identity, or
#          the range could not be read, or it is empty.
# Exit 2 : called wrong.
#
# Which answer sits on which code is deliberate. Under "set -e" a script that
# breaks somewhere inside itself exits 1, so 1 has to be the answer that is safe
# to give by accident. Here that is "this pull request is not signed" : a false
# red is read by a human who can see the commits for themselves, where a false
# green would let through exactly the thing this exists to catch, on a run that
# looks fine. It fails closed.
#
# Usage : .github/check-sign-off.sh <base-sha> <head-sha>

set -euo pipefail

if [ "$#" -ne 2 ]; then
  printf 'Usage : %s <base-sha> <head-sha>\n' "${0##*/}" >&2
  exit 2
fi

readonly BASE="$1"
readonly HEAD="$2"

# The trailer git itself writes with "commit -s", read as a TRAILER and matched
# on its SHAPE. Both halves are needed, and each closes a hole the other leaves.
#
# Searching the message body for the pattern passes a commit that merely QUOTES
# the rule -- CONTRIBUTING.md's own example, pasted into a commit message
# explaining the sign-off, is a well-formed line that certifies nobody, and git
# reports no trailer on such a commit while a grep over the body reports a match.
#
# Reading the trailer without looking at its value passes the other shape :
# "Signed-off-by:" followed by nothing, or by a name with no address, is what a
# broken git config produces and it certifies nobody just the same. The address
# only has to LOOK like one -- an "@" with something either side -- because
# whether a mailbox is reachable is not decidable from here and never will be.
readonly SIGN_OFF_VALUE_PATTERN='^.+ <[^[:space:]<>]+@[^[:space:]<>]+>[[:space:]]*$'

# The identity a Claude Code session commits under. Matched on the address and
# never on the name : a human contributor may be called anything, "Claude" is
# not a reserved word, and the address is what actually identifies the tool
readonly AGENT_EMAIL="noreply@anthropic.com"

# One command substitution per statement : a signal landing inside a second one
# in the same expansion gets its trap handler parsed with the substitution open
COMMITS=""
if ! COMMITS="$(git log --no-merges --format='%H' "$BASE..$HEAD" 2> /dev/null)"; then
  printf '::error::Could not read the commits between %s and %s. Checking out with fetch-depth 0 is what makes both ends of that range present\n' \
    "$BASE" "$HEAD" >&2
  exit 1
fi

# An empty range is refused rather than passed. A pull request that genuinely
# adds no commit is a state nobody needs this job's opinion on ; a range that
# resolves to nothing because the base or the head was computed wrong is the
# shape of a false green, and the two are indistinguishable from here. Both land
# on the refusal, for the reason the exit codes are chosen on above
if [ -z "$COMMITS" ]; then
  printf '::error::No commit between %s and %s. A range that resolves to nothing is refused rather than reported clean, since a base or head computed wrong looks exactly like this\n' \
    "$BASE" "$HEAD" >&2
  exit 1
fi

UNSIGNED_COUNT=0
AGENT_CERTIFIED_COUNT=0
CHECKED_COUNT=0

while IFS= read -r COMMIT; do
  [ -n "$COMMIT" ] || continue

  CHECKED_COUNT=$((CHECKED_COUNT + 1))

  SUBJECT=""
  SUBJECT="$(git log -1 --format='%s' "$COMMIT")"

  # git's own trailer parser rather than the message body : a line quoting the
  # rule inside a paragraph is not a trailer, and git is the authority on which
  # is which. Strictly stronger than a body search, and not complete -- a
  # well-formed line quoted at the very END of a message is parsed as a trailer
  # and still passes. That bound is measured, and written down so the next
  # reader who finds it knows it was known
  SIGN_OFFS=""
  SIGN_OFFS="$(git log -1 --format='%(trailers:key=Signed-off-by,valueonly)' "$COMMIT")"

  # One well-formed value is enough : a commit may carry several, and a
  # co-author's malformed line does not undo the author's certification
  if ! printf '%s\n' "$SIGN_OFFS" | grep -qE "$SIGN_OFF_VALUE_PATTERN"; then
    UNSIGNED_COUNT=$((UNSIGNED_COUNT + 1))
    printf '::error::%s "%s" carries no Signed-off-by\n' "${COMMIT:0:8}" "$SUBJECT" >&2
    continue
  fi

  # Signed -- but by whom ? A trailer naming only the agent satisfies the shape
  # above while naming nobody who can make the statement. Refused for that
  # reason, and only when it is the ONLY sign-off on the commit : one naming a
  # person alongside it is a person certifying, which is all the DCO asks
  # Filtered through the shape pattern first, and that is load-bearing rather
  # than tidy : the trailer output ends in a newline, so a bare "grep -v" would
  # see the empty line it leaves behind, find no agent address on it, and pass
  # every commit ever written. Only well-formed values are asked the question
  if printf '%s\n' "$SIGN_OFFS" | grep -E "$SIGN_OFF_VALUE_PATTERN" | grep -qivF "<$AGENT_EMAIL>"; then
    continue
  fi

  AGENT_CERTIFIED_COUNT=$((AGENT_CERTIFIED_COUNT + 1))
  printf '::error::%s "%s" is signed off under the agent identity, which certifies nobody\n' \
    "${COMMIT:0:8}" "$SUBJECT" >&2
done <<< "$COMMITS"

if [ "$UNSIGNED_COUNT" -eq 0 ] && [ "$AGENT_CERTIFIED_COUNT" -eq 0 ]; then
  printf 'All %d commits carry a sign-off\n' "$CHECKED_COUNT"
  exit 0
fi

# The two failures are reported apart because they are fixed apart, and telling
# one to do the other's remedy is how a contributor force-pushes for nothing
if [ "$UNSIGNED_COUNT" -gt 0 ]; then
  printf '\n%d of the %d commits in this pull request carry no sign-off.\n\n' "$UNSIGNED_COUNT" "$CHECKED_COUNT" >&2
  printf 'Adding one is your statement of the Developer Certificate of Origin, which is what\n' >&2
  printf 'lets this dual-licensed project offer your contribution under both of its licences.\n' >&2
  printf 'See CONTRIBUTING.md. To sign the commits already on this branch :\n\n' >&2
  printf '  git rebase --signoff %s\n  git push --force-with-lease\n\n' "$BASE" >&2
  printf 'and "git commit -s" from here on, or "git commit --amend -s" for the last one.\n' >&2
fi

if [ "$AGENT_CERTIFIED_COUNT" -gt 0 ]; then
  printf '\n%d of the %d commits in this pull request are signed off under the agent identity.\n\n' \
    "$AGENT_CERTIFIED_COUNT" "$CHECKED_COUNT" >&2
  printf 'A tool certifies nothing. The agent belongs in the author field or in a\n' >&2
  printf 'Co-Authored-By trailer, where git log, git blame and the contributor graph read\n' >&2
  printf 'it ; the Signed-off-by has to name the person whose review and merge make the\n' >&2
  printf 'certification true. See CONTRIBUTING.md, "Contributions written by an agent".\n\n' >&2
  printf '"git commit -s" derives the trailer from the author, so it writes this same\n' >&2
  printf 'commit again on a commit the agent authored. Pass the trailer explicitly :\n\n' >&2
  printf '  git commit --amend --trailer "Signed-off-by: Your Name <you@example.org>"\n' >&2
fi

exit 1
