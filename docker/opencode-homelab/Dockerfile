# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=zot.cloud5.ovh/opencode/oc-base:1.0.0

FROM ${BASE_IMAGE}

ARG ANSIBLE_CORE_VERSION=2.20
ARG ANSIBLE_LINT_VERSION=26.6.0

RUN pip3 install --no-cache-dir --break-system-packages \
        ansible-core==${ANSIBLE_CORE_VERSION}.* \
        ansible-lint==${ANSIBLE_LINT_VERSION} \
 && ansible --version | head -n 1 \
 && ansible-lint --version

COPY tests/verify-homelab.sh /usr/local/bin/verify-homelab.sh
RUN chmod +x /usr/local/bin/verify-homelab.sh

RUN command -v ansible && ansible --version | head -n 1 \
 && command -v ansible-lint && ansible-lint --version

WORKDIR /workspaces
ENTRYPOINT ["opencode"]