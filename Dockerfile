# The OTP release, built on hexpm's Elixir image and run on slim Debian.
# The base pins the closest published image to .tool-versions' 27.3.4.
FROM hexpm/elixir:1.17.3-erlang-27.3.4.16-debian-bookworm-20260803-slim AS build

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git curl ca-certificates && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

# Whole-context copy: Daedalus is a path dep, so a selective COPY
# buys little and breaks whenever the project list grows.
COPY . .

RUN mix deps.get --only prod

# GIT_SHA: /health reports it and deploy detection runs SHA ancestry
# against it. Sources, in order: the build arg, the .git directory if the
# context carries one, else "dev", which the CMD below replaces at start
# when the platform names the commit (RENDER_GIT_COMMIT).
ARG GIT_SHA=""
RUN sha="$GIT_SHA"; \
    if [ -z "$sha" ] && [ -d .git ]; then sha="$(git rev-parse HEAD 2>/dev/null || true)"; fi; \
    echo "${sha:-dev}" > /app/GIT_SHA

# The client and its storybook ship inside the image under priv/static,
# built here rather than at deploy time, so the preview serves what the
# PR built.
RUN cd client && npm ci && npm run build && npm run build-storybook && \
    rm -rf ../priv/static/storybook && mv storybook-static ../priv/static/storybook

RUN mix compile && mix release --overwrite

FROM debian:bookworm-slim

# git is the records port's one binary (Oneiroi.SimaQian.Git): import,
# rebuild and the nightly backup all run it. This stage shipped without
# it until 2026-11-01, when the first real import answered 500 on
# `enoent`; the build stage had it, so nothing that ran there noticed.
# test/oneiroi/runtime_image_test.exs holds this list to every binary
# the code calls.
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates git && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 MIX_ENV=prod
WORKDIR /app
COPY --from=build /app/_build/prod/rel/oneiroi ./
COPY --from=build /app/GIT_SHA /app/GIT_SHA

# Migrations run here, in the container's own start command, ahead of
# `start`, through `Oneiroi.Release.migrate`: a separate pre-deploy job
# is a second component whose environment goes stale the day a variable
# is added, and a migrator that fails stops the container before the
# health check answers, so the platform keeps the previous deployment
# serving. The first deploy ran without the `eval` line: the comment
# above described it and the command did not do it, so the application
# started against an unmigrated database and failed on the role its
# own migration creates. GIT_SHA is exported at start; a "dev" stamp
# yields to RENDER_GIT_COMMIT when the platform supplies one.
CMD ["/bin/sh", "-c", "sha=$(cat /app/GIT_SHA) && if [ \"$sha\" = dev ] && [ -n \"$RENDER_GIT_COMMIT\" ]; then sha=$RENDER_GIT_COMMIT; fi && /app/bin/oneiroi eval 'Oneiroi.Release.migrate()' && GIT_SHA=$sha exec /app/bin/oneiroi start"]
