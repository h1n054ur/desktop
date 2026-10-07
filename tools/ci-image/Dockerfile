# CI image for the h1n054ur/desktop monorepo: everything the jobs need, baked in once.
#   splitsh-lite 2.0.0  splits each folder into its own repo (built from source; needs libgit2 1.5, which bookworm ships)
#   gitleaks 8.30.1     secret scan (release binary, checksum-pinned)
#   python3, shellcheck the keybind check and script lint
# Build and push (when this file changes):
#   docker build -t <registry>/<owner>/desktop-ci:1 tools/ci-image
#   docker push <registry>/<owner>/desktop-ci:1
FROM golang:1.22-bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends libgit2-dev pkg-config && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v2.0.0 https://github.com/splitsh/lite.git /src
WORKDIR /src
RUN go build -o /out/splitsh-lite .
RUN curl -fsSL -o /tmp/gl.tgz https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
 && echo "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb  /tmp/gl.tgz" | sha256sum -c - \
 && tar -xzf /tmp/gl.tgz -C /out gitleaks

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgit2-1.5 git ca-certificates openssh-client python3 shellcheck \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/splitsh-lite /out/gitleaks /usr/local/bin/
# The workspace belongs to another user in CI and on the host; let git work there
RUN git config --system --add safe.directory '*'
