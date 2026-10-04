<!--
SPDX-FileCopyrightText: 2026 Tigerblue77 and the Claude Code Docker container image contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Working in this repository

This repository produces one thing: a Docker image with Claude Code installed in it,
published to `ghcr.io`. It contains no source code of its own. The CLI comes from the npm
package `@anthropic-ai/claude-code`, its runtime dependencies from apt, and nothing in this
tree is copied into the image. So every question here is about packaging, pinning and
publication, and none is about how Claude Code behaves: a defect in the tool belongs
upstream, in `anthropics/claude-code`, not here.

Two files carry all of it, and that is worth keeping. A change that seems to need a third
file is worth a second look before it is written.

## Layout

| File | What it holds |
| --- | --- |
| `Dockerfile` | The image: Node base per the rule below, pinned npm install, non-root `node` user, auto-updater off, no `VOLUME` |
| `.github/workflows/auto_update_pull_request_branches.yml` | Rebase every open, non-draft, conflict-free pull request that is behind `main` and was not opened by Dependabot, once `main` has been quiet for an hour after a push, falling back to a merge commit, and comment once on each one that conflicts. Best effort, and it needs a credential of its own: its header says which, and why the default token will not do |
| `.github/workflows/build-and-publish.yml` | Resolve the version from npm, build, run the image once to prove it runs, publish only when that version is not already there |
| `.github/workflows/dependabot-auto-merge.yml` | Queue Dependabot's minor and patch updates with `gh pr merge --auto`, never merge them directly |
| `.github/rulesets/main.json` | The live ruleset that protects `main`, its required checks included, in the form GitHub's "Import a ruleset" takes |
| `.github/check-ruleset.sh`, `.github/workflows/ruleset.yml` | Fail a pull request whose ruleset names a check no job reports |
| `.github/workflows/lint-workflows.yml` | The **actionlint** and **zizmor** checks, both required. Both tools are pinned: actionlint has its shell and Python integrations off, and zizmor runs `--offline`, which drops its four audits that need the network |
| `.github/zizmor.yml`, `.github/actionlint.yaml` | Their configuration, which each tool finds where it is. zizmor's states the one place this repository differs from its defaults, the version-tag policy; actionlint's ignores two false positives from its own action table, in one file |
| `README.md` | What the image is and how to run it |
| `LICENSE` | AGPL-3.0-only |

## Commands

```bash
# What CI does, in the order it does it
npm view @anthropic-ai/claude-code@stable version     # the version the workflow resolves
npm view @anthropic-ai/claude-code dist-tags          # stable, latest, and how far apart they are
docker build --build-arg CLAUDE_CODE_VERSION=<version> -t claude-code:dev .
docker run --rm claude-code:dev --version             # must report the version it was built with
```

`CLAUDE_CODE_VERSION` has no default and the `Dockerfile` refuses to build without it. That
is deliberate: a build that resolves its own version produces an image whose content depends
on the day it ran, which can be neither reproduced nor rolled back.

**A build needs a Docker daemon, and Claude Code on the web has none.** The binary is on the
PATH, so it looks runnable right up until it answers "cannot connect to the Docker daemon".
Say so rather than reporting a build that did not happen: piped into `tail` or `head` it
exits 0 whatever docker did, because the status is the pipe's last command. Nothing is lost
by leaving it out where it cannot run, since the workflow builds the image and runs it on
every pull request touching the `Dockerfile` or the workflow itself. It costs a CI round
trip, which is the price of not having a daemon rather than a reason to skip the check.

### Lint

```bash
# What lint-workflows.yml does, from the repository root
go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.12
"$(go env GOPATH)/bin/actionlint" -shellcheck= -pyflakes=
zizmor --offline .      # installed as the workflow's own step does, hash-checked from PyPI
```

Neither needs a Docker daemon, and a cold install of both took about fifteen seconds. Run
them on any change to a workflow or to `.github/dependabot.yml`: they are required checks,
so a finding found here saves a CI round trip.

## Invariants

These are settled decisions with a cost behind them. Do not "clean them up".

- **The base image follows a Node release line that is Active LTS, or a Current one
  within six months of becoming LTS.** Today that is `node:26-slim`: Current since
  5 May 2026, Active LTS around November 2026.

  The rule used to read "Node LTS base", and it was wrong twice over. It made no
  room for the only shape a Dependabot pull request on this line can have, and it
  had no way to express the thing actually being protected -- which is not the
  letter "LTS" but the guarantee that the line under a CLI shipped to other people
  keeps receiving security fixes for years, not weeks.

  A worked example, because this is the decision the rule exists to settle. Node 25
  reached end of life on 31 March 2026 and must never be the base: adopting it
  would mean shipping a runtime that receives nothing at all. Node 26 is Current
  rather than LTS, so a strict reading refuses it -- yet it is on the six-month
  path to LTS, it is the line Node's own security releases land on today, and
  refusing it would have meant reverting to 24 for eight weeks and then merging the
  identical bump again. The rule is written to say yes to the second and no to the
  first, which "LTS only" could not do.

  What it still refuses, and this is the part not to soften: an odd-numbered line,
  which never becomes LTS and dies within a year of its release, and any line
  already at end of life. When Dependabot proposes a major, check the status on
  <https://nodejs.org/en/about/previous-releases> before merging -- that page is
  the authority, and the answer changes twice a year.

- **The installed version is always pinned. Three different things are called "latest"
  here, and they are decided separately.**

  *What is installed* is an exact version passed as a build argument, never a bare
  `npm install -g @anthropic-ai/claude-code`. An image whose contents depend on the day it
  was built can be neither reproduced nor rolled back.

  *Which npm channel that version comes from* is `stable`, not `latest`. `latest` is
  whatever was published most recently; `stable` lags it by a few releases -- 27 of them
  when this was written -- and has therefore survived contact with other people. That is
  what an image somebody runs daily wants underneath it. Override with the `NPM_DIST_TAG`
  repository variable if that trade ever stops being the right one.

  *Which Docker tag moves* is `latest`, and this reverses an earlier decision. The
  objection to it was real and has not gone away: a moving tag means "whatever was pushed
  most recently", which is not a state anyone can roll back to. What answers it is that
  rolling back was never the moving tag's job -- the immutable `:<version>` tag is there
  for exactly that, and a base-image refresh deliberately leaves it alone. Against that,
  `latest` is the tag `docker pull <image>` resolves to when no tag is given, and an image
  that cannot be pulled without reading the README first is an image that does not get
  pulled. Override with `IMAGE_MOVING_TAG`.

  The moving tag used to be named after the npm channel, so the tag itself recorded which
  channel the image came from. Decoupling the two lost that, so the channel is now written
  on the image as a label, `io.github.dragnix-tigerblue77.claude-code.npm-dist-tag`. Do not
  drop it: the publishing workflow's own decision to rebuild reads labels back off the
  published image, and this one is how a human answers "which channel is this?" without
  guessing from a tag that no longer says.
- **Images float by default, and are pinned on purpose only where a database would lose
  its data.** An image is written with no tag at all -- `image: redis`, never
  `image: redis:latest` and never a tag held in a variable: no tag *is* `latest`, writing
  it out adds nothing, and a variable for it is a second place to keep in step with the
  first. The deployer pulls on every run, so each deployment brings the current release
  and its security fixes. The exception is a database -- PostgreSQL, MariaDB, MongoDB,
  Qdrant -- whose data lives only in its own volume: a major bump lands on a layout the
  new image does not read (PostgreSQL 18 moved its data directory, and starts on an empty
  one), so it is a deliberate move, made after a dump. It is pinned to the major it was
  initialised with, literally in the template, with the reason on the line above its
  `image:`. Redis and Valkey hold a cache and float. A variant tag a service genuinely
  needs is an exception of the same kind and says why in the same place.

  This repository publishes the moving tag `latest`, the one a pull with no tag resolves
  to, so the examples in the README, in this file and in the `Dockerfile` name the image
  and no tag. The image holds no database, so nothing here is pinned on that account.
- **Every workflow starts with the two SPDX lines**, before its `name:`, in the form used
  across this owner's repositories:

  ```yaml
  # SPDX-FileCopyrightText: 2026 Tigerblue77 and the Claude Code Docker container image contributors
  # SPDX-License-Identifier: AGPL-3.0-only
  ```

  The repository is public and AGPL-3.0-only. A file whose licence is stated only by a
  `LICENSE` at the root loses that statement the moment it is copied out on its own, which
  is what happens to a workflow that someone finds useful.
- **Every `actions/checkout` sets `persist-credentials: false`, unless a later step of the
  same job really authenticates through git.** By default the action keeps the job's token
  for the steps that follow. v7 writes it to a config file under `$RUNNER_TEMP` and points
  the checked-out repository at it with `includeIf` entries, so any later step can use it,
  or read it back through git, until the job's cleanup removes it. With the option off,
  the action removes the credential it set up when its own step ends, right after it has
  fetched with it, so no later step inherits it. That removes the copy the checkout
  leaves behind and not the token: a step that names `secrets.GITHUB_TOKEN`, as the
  registry login does, still has it. Nothing here needs more: no step pushes or fetches
  through git after a checkout, and the workflows that talk to GitHub do it through `gh`
  with a token they are handed explicitly. A checkout that has to keep the credential
  leaves it on and names, in a comment beside it, the step that needs it.
- **Every commit carries a `Signed-off-by`, and it never names the agent.**
  `CONTRIBUTING.md` states the rule and the `Sign-off` workflow enforces it on every
  pull request. It is not a formality here: the project is dual-licensed, and the
  trailer is the record that a contribution could be offered under both arms, which
  is what keeps the commercial one grantable. A session authors its commits under
  the agent — in the author field or in a `Co-Authored-By` trailer, which is where
  `git log`, `git blame` and the contributor graph read who wrote the work — and
  signs off as the maintainer, whose act of reviewing and merging is the
  certification. `git commit -s` derives the trailer from the author, so on a commit
  the agent authored it writes the one shape the check refuses; pass it explicitly:

  ```bash
  git commit --trailer "Signed-off-by: Tigerblue77 <37409593+tigerblue77@users.noreply.github.com>"
  ```
- **Dependabot's minor and patch updates merge themselves once CI is green, in every
  repository of this owner.** A Dependabot pull request sitting open with every check green
  is a defect in that process, not a task for a human. Here, as on wader/postfix-relay which
  is the reference, GitHub does the waiting: `dependabot-auto-merge.yml` queues the merge with
  `gh pr merge --auto` and never merges directly, and what it waits for is
  `.github/rulesets/main.json`, which `.github/check-ruleset.sh` keeps naming jobs that exist.
  A private repository, where GitHub enforces no ruleset, does the waiting in its own workflow
  instead; the rule is the same. What gets through is decided by the build, not by a guess
  about which ecosystem is risky: majors wait for a human, and so does anything red.
- **A release is seven days old before Dependabot proposes it, on both entries, and that
  covers less than it sounds like.** Dependabot's own default is three days, applied to
  version updates even when no cooldown is configured, and `.github/dependabot.yml`
  lengthens it with `cooldown: default-days: 7` on each entry, four days more than the
  default. The auto-merge above merges a minor or patch update the moment the build is
  green, and a green build says nothing about whether a new release can be trusted, so the
  delay is what keeps one published this morning, a compromised one included, off `main`
  before anybody could notice and withdraw it. Today it covers less than that. Every
  action is pinned to a major tag, and Dependabot keeps the precision of the ref it finds:
  it never proposes `v7.x.y` for an `@v7` pin, only the next major, which is never
  auto-merged and waits for a human (both pull requests it has opened here were majors).
  The cooldown therefore delays the proposal of a major, and guards an unattended merge
  only once an entry gains a minor or patch stream. It does not cover a floating tag at
  all: when an action's maintainer moves `v7`, the workflows follow at once, with no pull
  request and so no delay, and only a pin to a full-length commit SHA prevents that. The
  maintainer decided against that pin, and this invariant does not reopen it. The `docker`
  entry has the same number although nothing it proposes merges unattended, since every
  update it can raise is a Node major that waits for a human: written out, it leaves the
  file with no exception to explain. A cooldown holds back version updates only, so a
  security update is never delayed by it. The number is the maintainer's to change, and
  there is one per entry. `default-days` is the only duration key these two ecosystems
  take: `semver-major-days` and its siblings exist for semver ecosystems such as pip and
  npm, which are not watched here, and `include` and `exclude` narrow a cooldown to chosen
  dependencies. `exclude` is what exempts one outright; the absence of a block is the
  default of three days, not an exemption. Dependabot validates the file on the pull
  request itself, as the `.github/dependabot.yml` check run ("Dependabot config file
  validation"), which catches a parse or schema error. What Dependabot then does with it
  shows only on Insights > Dependency graph > Dependabot, after the merge, so look there
  when this file changes.
- **Pull requests are kept level with the default branch, and never required to be, in
  every repository of this owner.** "Require branches to be up to date before merging" stays
  off -- `.github/rulesets/main.json` records it as `strict_required_status_checks_policy:
  false` -- because whatever cannot be updated automatically would be blocked rather than
  behind: a conflict, a fork, a draft, and every pull request after a Dependabot merge, which
  starts no workflow. `auto_update_pull_request_branches.yml` does the updating instead, as
  best effort and once `main` has been quiet for an hour after a push, so that a series of
  merges is followed by one pass and not one per merge. The hour is a sleep at the start of
  the run, which the next push cancels, and not a schedule, which GitHub started here every
  few hours instead of hourly (#53). A merge Dependabot queues starts no workflow, so no wait
  either: what it leaves behind is brought level after the next push made any other way. A
  pull request that conflicts gets one comment saying so, deleted once the conflict is
  resolved. The workflow leaves Dependabot's own pull requests to Dependabot: a rebase
  pushed by anyone else strips the signature the auto-merge checks before it acts (#37). It
  runs here because the repository is public and its minutes cost nothing, while a private
  repository carries the same file switched off behind the `PULL_REQUESTS_UPDATE_ENABLED`
  variable. Shared like the rule above (#35).
- **The default branch is `main`.** Branch from it, target it. Other repositories of this
  owner still use `master`, and a pull request opened against a branch that does not exist
  here fails at the API call, after the work is done.
- **Open a pull request assigned to `tigerblue77`, and never as a draft.** Both are fields
  on the call that creates it, and the session that would come back to repair them has ended
  by then. A web session's harness defaults to draft, which buys nothing here -- a draft has
  to be converted before it can be merged at all -- and unassigned work is not on anybody's
  list, so it is remembered rather than scheduled.
- **Everything here is written in English, pull requests included.** The repository is
  public and the audience for an image of an Anthropic CLI is not a French-speaking one.
  This rule covers the tree and commit messages, the next one issues and pull requests.

  **The closing keyword is written in English, whatever language the rest of the body is
  in:** `Closes #NN` or `Fixes #NN`. GitHub recognises no other form, and it fails
  silently — `Ferme #14` renders as a perfectly ordinary link to the issue, the pull
  request merges, and the issue stays open with nobody notified. Measured here, while pull
  request bodies were still written in French: #1, #14 and #15 were each fully delivered
  and each sat open afterwards, because their pull requests said "Ferme" when they merged.
- **Issues and pull requests are written in English, and one that is not is flagged.**
  Titles, bodies and comments, in every repository but the private ones whose own
  instructions put issues and pull requests in French, the private repositories of the
  `Dragnix-Tigerblue77` organisation among them, where code and commit messages still
  stay in English. This one is in that organisation but public, so the exemption does not
  reach it. An issue or a pull request found breaking this, in a repository it covers, is
  never let pass silently: the maintainer is told, every time, with the link, and offered
  a translation, which is made once they agree.
  Shared like the rules above (#39, extended to pull requests by #41). What was opened
  here before the rule reached it was translated once it did.
- **Everything a session posts on GitHub is signed, with the link to the session that wrote
  it.** An issue, a pull request, a comment, a review and a reply on a review thread each
  end with a blank line, a `---` rule and this line, and an edit to one keeps it:

  ```
  _Generated by [Claude Code](https://claude.ai/code/session_<id>) and supervised by @tigerblue77._
  ```

  The link is the one to the session itself, the address the session's own attribution
  instructions give, so that the maintainer can go from any issue, pull request or comment
  straight to the conversation that produced it -- the only place the reasoning that never
  reached the text still lives. The tooling appends a footer of its own to some posts, a
  pull request for one, and only the signature stays: once the post exists, its body is
  edited so that the signature is the last thing in it, since two lines saying the same
  thing are noise and only this one carries the maintainer's name. An issue opened without
  a signature is the case this rule exists for: nothing then links it to its conversation.
  The wording is the maintainer's, "supervised by" and not "reviewed by", and it is one
  fixed formula in every repository, whatever the language of the text above it -- English
  here, and not in every repository of this owner, as the rule above says -- because it is
  a signature and not prose. A commit message is not covered: it credits the agent in a
  `Co-Authored-By` trailer and carries the maintainer's `Signed-off-by`, as the rule on
  sign-offs above says. Shared with every repository of this owner that carries agent
  instructions, and written out in full in each.
- **Another repository of this owner is cited only where this one calls it**: pulls its
  image, vendors its code, downloads its release, or registers something for it. Citing
  means naming it, or pointing to its issues or pull requests. It is never cited to say
  where a rule or a lesson came from, that a copy of a rule exists elsewhere, or how the
  other one does it. A citation of that kind is a dependency with nothing keeping it
  true: the other repository renumbers, is renamed, moves or goes private, and the
  sentence citing it goes stale here without anything failing. So a rule shared across
  this owner's repositories is written out here in full, standing on its own, with no
  citation of its origin.

  **A public repository never names a private one**, not even one it calls, nor cites
  its issues or pull requests, nor describes what it holds: not in a file, a commit
  message, a branch name, an issue, a pull request or a comment. This repository is
  public, so everything written here is published, and neither the history nor an
  edited issue takes a name back once it is out. "A private repository of this owner" is
  as specific as a reference to one gets. Naming the public `Dragnix-Tigerblue77`
  organisation is fine. Shared like the rules above (#47, #50).
- **Workflows are linted by actionlint and zizmor, both required, with pinned tools and
  without the audits that need the network.** `.github/workflows/lint-workflows.yml`
  reports them under the names of their jobs, which are the contexts in
  `.github/rulesets/main.json`. That file is a record and not the live setting: a check is
  required only once the file has been imported again under Settings > Rules. The
  `pull_request` trigger has no `paths` filter, for the reason `build-and-publish.yml`
  gives: a filtered workflow does not report a skipped check, it reports nothing, and the
  pull request waits for it for ever. Both tools are pinned and nothing bumps them, since
  Dependabot reads `uses:` lines and not these, so a newer release, which usually knows
  more mistakes, is a deliberate edit that can turn a required check red on a tree nobody
  touched. actionlint, v1.7.12, is installed with `go install`, whose checksum database
  authenticates the module, and runs with `-shellcheck= -pyflakes=`: those integrations
  would make the verdict depend on whichever versions the runner image carries that week.
  zizmor, 1.30.1, is installed from PyPI with `--require-hashes`, as the manylinux wheel
  whose hash the step states, and runs `--offline`, because its online audits ask advisory
  data that changes daily. That drops four audits, `impostor-commit`,
  `known-vulnerable-actions`, `ref-confusion` and `stale-action-refs`, the ones that ask
  GitHub what a reference resolves to or whether an action has a published advisory. They
  matter here, since the policy below accepts symbolic refs: a moved `v7` is caught by
  none of what runs. Not everything the jobs read is pinned either. The runner image's Go
  and Python, `actions/checkout@v7` itself and the Go toolchain that actionlint's `go.mod`
  makes `go install` select all float, so "pinned" is a statement about the two tools and
  not about the whole job.

  A finding is fixed rather than ignored: no audit is switched off, no threshold is lowered
  and no `# zizmor: ignore` comment exists. What the configuration does state is
  deliberate. `.github/zizmor.yml` accepts actions on a version tag, which is the
  maintainer's decision and not the tool's default of a commit hash, and that is its only
  setting. It accepts a risk and does not remove it: Dependabot follows the major tag and
  proposes the next major, and nothing sits between a maintainer moving the tag and the
  workflows, which only a full-length commit SHA pin removes. zizmor's `artipacked` audit
  fails a checkout that omits `persist-credentials: false`, a low-severity finding
  included. Its `dependabot-cooldown` audit runs at its default threshold of seven days,
  which is the cooldown `.github/dependabot.yml` states, but in 1.30.1 it judges only the
  first `updates` entry and stops, so it is a partial check of that decision and not a pin.
  `.github/actionlint.yaml` ignores two messages, in one workflow, about
  `actions/create-github-app-token@v3`: actionlint's built-in table of action inputs
  predates the `client-id` input that action's `action.yml` has at `v3`. The workflow is
  right and the table is stale, so drop the file when a bumped actionlint stops reporting
  them.

## The authentication trap

Claude Code keeps its authentication state in **two** places: the directory `~/.claude/`
**and** the file `~/.claude.json`, which sits **beside** that directory rather than inside
it. A volume or bind mount on `~/.claude` alone therefore persists half the state and loses
the other half every time the container is recreated. The symptom is a login that
disappears for no visible reason, which gets diagnosed as a bug in the CLI long before
anyone suspects the mount. Mount the whole home directory:

```bash
docker run --rm -it \
  -v claude_home:/home/node \
  -v "$PWD:/workspace" \
  ghcr.io/dragnix-tigerblue77/claude-code-docker-container
```

This is why the `Dockerfile` declares no `VOLUME` at all: an anonymous volume on the wrong
path would make the half-persisted state the default for everybody who runs the image
without reading anything. No credential is ever baked into the image; they arrive at run
time, and each person authenticates with their own.

## Environment

`.claude/settings.json` pre-approves a short list of commands, so a session runs them without
stopping to ask: `docker build`, `docker run --rm`, `npm view`, and the read-only half of
`git` (`status`, `diff`, `log`, `show`). They are what checking a change here consists of.

That list is a standing grant to every session opened in this repository, so adding to it is
a decision to argue rather than a line to append. Two of its shapes are deliberate.
`docker run` is granted only with the `--rm` prefix: that flag sandboxes nothing, it simply
pins the shape this repository actually uses -- build, run once, throw away -- and leaves a
container that outlives the session, or one given a bind-mounted home directory, as
something worth stopping to ask about. And `git` is granted by subcommand rather than as
`git:*`, because the same binary that reads the tree also rewrites and pushes it.

`.claude/hooks/session-start.sh` runs at the start of every remote session, and it
**installs nothing**, although installing what CI gates on is what such a hook is usually
for. Nothing here is gated on a tool a hook could apt-install: the one thing a session needs
beyond `git` is a Docker daemon, which is not a package. What it configures instead is the
one rule a session cannot satisfy by remembering it — **`git signoff`**, an alias that
commits with the maintainer's `Signed-off-by` passed explicitly.

Use it instead of `git commit -s`. That flag derives the trailer from the author, so on a
commit authored under the agent it writes precisely the shape the Sign-off check refuses.

The hook is repository-local, best-effort and never blocks a session: if it cannot set the
alias it says so and tells you the `--trailer` form to pass by hand.

If a lint gates pull requests, installing it in this same hook is the way to keep its
findings out of a CI round trip, on the terms the hook already keeps: only in a remote
session, best effort, and a failure reported rather than blocking the session. Two do now,
actionlint and zizmor on the workflows, and the hook does not install them yet. A cold
install of both took about fifteen seconds, half of the 30-second timeout
`.claude/settings.json` gives the hook, and a hook that overruns it stops standing up
`git signoff`, which is what it is there for. Moving them in is therefore a change to make
together with that timeout, not a line to append; until then, the commands under
[Lint](#lint) are the way. `hadolint` on the `Dockerfile` or `yamllint` would be the same
decision.
