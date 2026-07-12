# Common OpenCode server image — extends ghcr.io/anomalyco/opencode with shared
# tooling used by all per-project instances (ansible, bicep, jq, git, ssh-client).
#
# Per-project instances (docker/opencode-homelab/, docker/openopencode-prospera/)
# reference this image directly via `image: opencode-server:latest` and rebuild
# it locally during Ansible runs (see docker_opencode_instance role).
ARG OPENCODE_BASE=ghcr.io/anomalyco/opencode:latest
FROM ${OPENCODE_BASE}

ENV OPENCODE_SERVER_HOSTNAME=0.0.0.0 \
    OPENCODE_SERVER_PORT=4096

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ansible \
        ansible-lint \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        sudo \
    && curl -fsSL -o /usr/local/bin/bicep \
        https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64 \
    && chmod +x /usr/local/bin/bicep \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash opencode \
    && mkdir -p /workspace \
    && chown -R opencode:opencode /home/opencode /workspace

USER opencode
WORKDIR /workspace

EXPOSE 4096

CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
