<div id="top"></div>

# Claude Code Docker image

A Docker image with [Claude Code](https://claude.com/claude-code) preinstalled, rebuilt automatically whenever a new version is published to npm.

There is no official image. Anthropic publishes a Dev Container Feature and calls its own reference container « a working example rather than a maintained base image ». This repository fills that gap, and modifies nothing : the binary inside is the one Anthropic publishes, installed from npm, untouched.

## Table of contents
<ol>
  <li><a href="#what-this-image-is-not">What this image is not</a></li>
  <li><a href="#requirements">Requirements</a></li>
  <li><a href="#supported-architectures">Supported architectures</a></li>
  <li><a href="#available-tags">Available tags</a></li>
  <li><a href="#usage">Usage</a></li>
  <li><a href="#authentication">Authentication</a></li>
  <li><a href="#whats-inside-the-image">What's inside the image</a></li>
  <li><a href="#how-the-image-is-built-and-updated">How the image is built and updated</a></li>
  <li><a href="#troubleshooting">Troubleshooting</a></li>
  <li><a href="#contributing">Contributing</a></li>
  <li><a href="#license">License</a></li>
</ol>

<!-- WHAT THIS IMAGE IS NOT -->
## What this image is not

Worth saying first, because it decides whether this repository is of any use to you :

- **It is not a fork of Claude Code.** It was one, briefly. The upstream repository holds a changelog, documentation, plugins and issues — not the source of the command-line tool, which ships as an npm package. A fork bought nothing and carried twelve of Anthropic's issue-triage workflows along with it, so it was deleted and this repository started clean.
- **It is not a modified Claude Code.** One `npm install -g`, at a pinned version. Anthropic's terms permit hosting the unmodified binary, and that is exactly what happens here.
- **It is not a way to share one subscription between several people.** Each person authenticates with their own credentials. Routing requests through somebody else's Free, Pro or Max plan is not permitted, and this image does nothing to help you do it.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- REQUIREMENTS -->
## Requirements

- **Docker.** Nothing else — no Node.js on the host, no npm, no global install.
- **A Claude account or an Anthropic API key.** The image ships no credentials and cannot obtain any on your behalf.
- **A writable volume for the home directory.** Not optional : without it, you re-authenticate every single time the container is recreated. See [Authentication](#authentication).

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- SUPPORTED ARCHITECTURES -->
## Supported architectures

| Architecture | Published |
| --- | --- |
| `linux/amd64` | Yes |
| `linux/arm64` | Not yet |

Only `amd64` is built, deliberately. Every machine this image was written for is x86, and building both would double the time of every run to publish something nobody pulls. Adding `arm64` is a two-line change to the workflow the day an ARM machine turns up — open an issue rather than working around it.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- AVAILABLE TAGS -->
## Available tags

| Tag | What it points at |
| --- | --- |
| `latest` | The moving tag, rebuilt whenever a new Claude Code release appears on the followed channel or the base image gets security fixes. **Use this one** unless you have a reason not to. |
| `<version>` | One exact version, `2.1.236` for instance. Immutable : once published it is never rebuilt or moved, which is what makes it the thing to pin and the thing to roll back to. |

**`latest` does not mean "the newest Claude Code".** The image is built from npm's `stable` channel, which trails npm's own `latest` by a few releases — 27 of them at the time of writing — and has therefore survived contact with other people. That lag is deliberate for an image people run every day : it is a good trade against being the one who finds the regression.

The two names are separate settings, and either can be changed without touching code : `NPM_DIST_TAG` picks the npm channel the image is built from, `IMAGE_MOVING_TAG` picks the Docker tag it is published under. The channel a given image actually came from is recorded on it as a label, so you never have to guess :

```bash
docker image inspect ghcr.io/dragnix-tigerblue77/claude-code-docker-container:latest \
  --format '{{index .Config.Labels "io.github.dragnix-tigerblue77.claude-code.npm-dist-tag"}}'
```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- USAGE -->
## Usage

### Docker CLI

```bash
docker run --rm -it \
  -v claude_home:/home/node \
  -v "$PWD:/workspace" \
  ghcr.io/dragnix-tigerblue77/claude-code-docker-container:latest
```

The entry point is `claude` itself, so anything you would pass to the command line goes at the end :

```bash
docker run --rm -it \
  -v claude_home:/home/node \
  -v "$PWD:/workspace" \
  ghcr.io/dragnix-tigerblue77/claude-code-docker-container:latest \
  --version
```

### Docker Compose

```yaml
services:
  claude-code:
    image: ghcr.io/dragnix-tigerblue77/claude-code-docker-container:latest
    volumes:
      - claude_home:/home/node
      - ./:/workspace
    stdin_open: true
    tty: true

volumes:
  claude_home:
```

`stdin_open` and `tty` are both needed : Claude Code is an interactive terminal program, and without them it starts and immediately finds nothing to read.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- AUTHENTICATION -->
## Authentication

No credentials are baked into the image. You sign in on first run, and the state persists in the volume mounted on the home directory.

### Mount the whole home directory, not just `~/.claude`

This is the one thing worth reading twice. Authentication state lives in **two** places :

```
/home/node/.claude/        a directory
/home/node/.claude.json    a file, BESIDE that directory — not inside it
```

Mount only `/home/node/.claude` and you persist half the state. The container will sometimes come back authenticated and sometimes not, with no pattern a person can see, and the obvious diagnosis — « the volume is not working » — is wrong, because it is. That is why this image declares no `VOLUME` of its own : a volume on the directory alone would look correct and behave badly, and nothing is worse than a default that fails quietly.

Mount `/home/node` and both are covered.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- WHATS INSIDE THE IMAGE -->
## What's inside the image

| | Why it is there |
| --- | --- |
| `node:24-slim` | Node 24 « Krypton » is the Active LTS. The package itself only asks for Node ≥ 18, so this is a choice of a supported base rather than a constraint. |
| `@anthropic-ai/claude-code` | Installed at a **pinned** version, supplied as a build argument. An image whose contents depend on the day it was built cannot be reproduced, and cannot be rolled back. |
| `git` | Claude Code reads and writes repositories. |
| `ripgrep` | Its file search falls back to a much slower path without it. |
| `jq` | Ubiquitous in the shell snippets Claude Code writes. |
| `less` | Pager for long output. |
| `ca-certificates` | TLS to the API and to package registries. |

Two settings are worth knowing about :

- **The auto-updater is disabled** (`DISABLE_AUTOUPDATER=1`). The image is rebuilt whenever a new version is published, so a binary that rewrote itself inside a container recreated from that image on every restart would be making a change that silently disappears.
- **The container runs as a non-root user** (`node`), with `/workspace` as its working directory.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- HOW THE IMAGE IS BUILT AND UPDATED -->
## How the image is built and updated

A workflow runs **every Monday**, on every pull request, and on demand.

On a schedule or on demand it asks npm what the followed dist-tag resolves to, asks the registry whether that version is already published, and **stops there if it is**. A cron that rebuilt every time would publish fifty-two identical images a year and make the tag history useless for telling when anything actually changed.

On a pull request it stops one step short of the registry : it resolves the version, builds, and runs the image, then skips the login and the push.

Either way, **the image is executed before it is pushed** : `claude --version` has to report the version it was built with. An image that builds is not an image that starts, and the failures worth catching here — a base tag that moved, a package missing from the distribution, an entry point installed without being executable — are invisible in a diff.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- TROUBLESHOOTING -->
## Troubleshooting

### It asks you to sign in every time

The home directory is not being persisted, or only half of it is. See [Authentication](#authentication) : `~/.claude.json` sits beside `~/.claude`, and both have to survive. Mount `/home/node`, not `/home/node/.claude`.

### `docker pull` fails with `denied` or `unauthorized`

The package is created **private** on its first publication. Make it public on the package's own settings page, or authenticate the pull with a token carrying `read:packages`.

### The container starts and exits immediately

Claude Code is interactive. `docker run` needs `-it`, and a Compose service needs `stdin_open: true` and `tty: true`. Without them it finds no terminal to read from and stops.

### It cannot write in `/workspace`

The container runs as the `node` user, whose numeric identifier is `1000`. A directory mounted from the host that belongs to another identifier will be read-only to it. Either adjust the ownership on the host, or run with `--user "$(id -u):$(id -g)"` — in which case the home directory volume has to be writable by that identifier too.

### The weekly build published nothing

That is the normal outcome when npm has not released anything since the last run. The run's summary says so explicitly rather than leaving you to guess.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

Issues and pull requests are welcome. A few conventions this repository holds to :

- **Images are pinned**, never `:latest`. Reproducibility and the ability to roll back both depend on it.
- **Workflow files carry an SPDX header.**
- **Pull requests are never opened as drafts.**
- The default branch is `main`.
- Documentation here is in **English**, the repository being public. Issues are in French.

See [`CONTRIBUTING.md`][link-to-contributing-file] for the rest, including what contributing implies about licensing.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- LICENSE -->
## License

[![License: AGPL v3][agpl-shield]][agpl] [![Commercial licence available][commercial-shield]][link-to-commercial-license-file]

This project is dual-licensed.

**By default, it is free software under the [GNU Affero General Public License version 3][agpl]** (`AGPL-3.0-only`). You may use it, study it, modify it and redistribute it, at no cost and with no formality. The one thing asked in return is reciprocity : if you distribute it — as files, as an image, or inside a product — the people who receive it must get the corresponding source under those same terms. The full text is in [`LICENSE`][link-to-license-file].

Running the container is never restricted. On a homelab, at work, in production, at any scale : the AGPL asks nothing of you for that, and no permission is needed.

**A [separate commercial licence][link-to-commercial-license-file] is available** for parties who cannot meet those obligations — typically a vendor embedding this in a product whose source cannot be published, or anyone needing a warranty, an indemnity or a support commitment, none of which the AGPL provides.

### What you may do

**Using it**

| | Under `AGPL-3.0-only` |
|---|---|
| Run it in a homelab | ✅ |
| Run it at work, in production, at any scale | ✅ no permission needed |
| Modify it for your own use, without distributing it | ✅ |
| Redistribute it, modified or not, commercially or not | ✅ provided the corresponding source goes with it |
| Combine it with GPL / AGPL code | ✅ |
| Patent licence | ✅ granted (§11) |

**Putting it inside something you ship**

| | What you need |
|---|---|
| Ship it in your product, publishing your modified source | ✅ nothing — the AGPL covers it |
| Ship it in your product, keeping your source closed | 💼 commercial licence |
| Get a warranty, an indemnity or a support commitment | 💼 commercial licence |

The short version : **using** it never requires a commercial licence, and never requires permission. Only **conveying** it while withholding the corresponding source does.

### What this licence does and does not cover

It covers **this repository** — the Dockerfile, the workflow, the documentation. It does **not** cover Claude Code itself, which remains subject to [Anthropic's terms][anthropic-terms], nor the other software the published image contains : the Node base image, `git`, `ripgrep`, `jq` and `less`, each under its own licence. Those are aggregated with this work, not derived from it, and their terms travel inside the image.

Copyright notices, attribution and the third-party terms that apply to the published image are recorded in [`NOTICE`][link-to-notice-file].

[agpl]: https://www.gnu.org/licenses/agpl-3.0
[agpl-shield]: https://img.shields.io/badge/License-AGPL%20v3-blue.svg
[commercial-shield]: https://img.shields.io/badge/Commercial%20licence-available-brightgreen.svg
[anthropic-terms]: https://code.claude.com/docs/en/legal-and-compliance
[link-to-license-file]: ./LICENSE
[link-to-commercial-license-file]: ./LICENSE-COMMERCIAL.md
[link-to-notice-file]: ./NOTICE
[link-to-contributing-file]: ./CONTRIBUTING.md

<p align="right">(<a href="#top">back to top</a>)</p>
