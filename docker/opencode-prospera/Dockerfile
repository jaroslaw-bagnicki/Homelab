# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=opencode-base:multistage-mcr
ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:8.0-alpine

FROM ${DOTNET_SDK_IMAGE} AS dotnet_src

FROM ${BASE_IMAGE}

COPY --from=dotnet_src /usr/share/dotnet /usr/share/dotnet
RUN ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet

RUN dotnet --list-sdks

COPY tests/verify-prospera.sh /usr/local/bin/verify-prospera.sh
RUN chmod +x /usr/local/bin/verify-prospera.sh

RUN command -v dotnet && dotnet --list-sdks

WORKDIR /workspaces
ENTRYPOINT ["opencode"]