#!/usr/bin/env bash
# Idempotent wrapper around the official installer — mirrors the oneliner.
[ -x "$HOME/.opencode/bin/opencode" ] || curl -fsSL https://opencode.ai/install | bash