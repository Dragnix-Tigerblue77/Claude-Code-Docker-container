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
| `.github/workflows/build-and-publish.yml` | Resolve the version from npm, build, run the image once to prove it runs, publish only when that version is not already there |
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
- **Every workflow starts with the two SPDX lines**, before its `name:`, in the form used
  across this owner's repositories:

  ```yaml
  # SPDX-FileCopyrightText: 2026 Tigerblue77 and the Claude Code Docker container image contributors
  # SPDX-License-Identifier: AGPL-3.0-only
  ```

  The repository is public and AGPL-3.0-only. A file whose licence is stated only by a
  `LICENSE` at the root loses that statement the moment it is copied out on its own, which
  is what happens to a workflow that someone finds useful.
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
- **The default branch is `main`.** Branch from it, target it. Other repositories of this
  owner still use `master`, and a pull request opened against a branch that does not exist
  here fails at the API call, after the work is done.
- **Open a pull request assigned to `tigerblue77`, and never as a draft.** Both are fields
  on the call that creates it, and the session that would come back to repair them has ended
  by then. A web session's harness defaults to draft, which buys nothing here -- a draft has
  to be converted before it can be merged at all -- and unassigned work is not on anybody's
  list, so it is remembered rather than scheduled.
- **Everything committed here is written in English.** The repository is public and the
  audience for an image of an Anthropic CLI is not a French-speaking one. Issues and pull
  requests are written in French, which is the maintainer's working language; that stops at
  the tree.

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
  ghcr.io/dragnix-tigerblue77/claude-code-docker-container:stable
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

There is no `SessionStart` hook here, unlike this owner's other repositories. A hook earns
its synchronous seconds by installing what CI will gate on, and nothing here is gated on a
tool a hook could install: the one thing a session needs beyond `git` is a Docker daemon,
which is not an apt package. If a lint ever gates pull requests -- `hadolint` on the
`Dockerfile`, `actionlint` or `yamllint` on the workflow -- installing it in a hook is the
way to keep those findings out of a CI round trip, and the hook in
`tigerblue77/dell_idrac_fan_controller_docker` is the model to copy.
