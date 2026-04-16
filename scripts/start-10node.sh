#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
sudo docker compose up -d --remove-orphans
