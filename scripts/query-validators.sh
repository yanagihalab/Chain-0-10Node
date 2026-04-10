#!/usr/bin/env bash
set -euo pipefail
RPC_PORT="${RPC_PORT:-37657}"
curl -s "http://localhost:${RPC_PORT}/validators" | jq '.result.validators[] | {address, voting_power, proposer_priority}'
