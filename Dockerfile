# Node 24 "Krypton" is the Active LTS. The package itself only asks for Node >= 18
# (its "engines" field), so this is a deliberate choice of a supported base rather
# than a constraint coming from upstream.
#
# Pinning this base by digest would make the build fully reproducible. It is left
# on the tag for now so that base-image security updates arrive on their own; if
# reproducibility ever matters more than that, pin it here.
FROM node:26-slim

# The exact version to install, supplied by the workflow. Never left unpinned:
# an image whose content depends on the day it was built cannot be reproduced,
# and cannot be rolled back to a known-good state.
ARG CLAUDE_CODE_VERSION

ARG TZ=Etc/UTC
ENV TZ="${TZ}"

# git             : Claude Code reads and writes repositories
# ripgrep         : its file search falls back to a much slower path without it
# less            : pager for long output
# jq              : ubiquitous in the shell snippets Claude Code writes
# ca-certificates : TLS to the API and to package registries
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      jq \
      less \
      ripgrep \
 && rm -rf /var/lib/apt/lists/*

# --allow-scripts names this one package on purpose. npm 11 refuses lifecycle
# scripts by default, and without it the install SUCCEEDS while quietly skipping
# the package's own postinstall (node install.cjs) -- "claude --version" still
# answers, so nothing looks wrong until something much later does. Naming a
# single package keeps scripts refused for everything else, including anything
# that arrives later as a transitive dependency.
RUN test -n "${CLAUDE_CODE_VERSION}" \
 && npm install -g --allow-scripts=@anthropic-ai/claude-code \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force

# The image is rebuilt whenever a new version is published, so the CLI must never
# rewrite itself at runtime: a binary that updates itself inside a container
# recreated from the image on every restart is a change that silently disappears.
ENV DISABLE_AUTOUPDATER=1

# The base image ships a "node" user. /workspace has to belong to it before the
# USER switch, or the first write into the working directory fails.
RUN mkdir -p /workspace && chown node:node /workspace

# No VOLUME is declared here, on purpose. Authentication state lives in TWO
# places: ~/.claude/ AND ~/.claude.json, which sits BESIDE that directory rather
# than inside it. A volume on ~/.claude alone would persist half the state and
# lose the other half on every recreation -- a failure that looks like a random
# logout. Mount the whole home directory instead:
#
#   docker run --rm -it \
#     -v claude_home:/home/node \
#     -v "$PWD:/workspace" \
#     ghcr.io/dragnix-tigerblue77/claude-code-docker-container:stable

USER node
WORKDIR /workspace

ENTRYPOINT ["claude"]
