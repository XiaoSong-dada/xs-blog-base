#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

if [[ ! -f ".env" ]]; then
  echo "[deploy] missing .env in $ROOT_DIR"
  echo "[deploy] create it from .env.example before deploying"
  exit 1
fi

echo "[deploy] pulling latest base repo"
git pull --ff-only

echo "[deploy] syncing submodules"
git submodule sync --recursive
git submodule update --init --recursive

echo "[deploy] validating compose"
docker compose -f docker-compose.yml config --quiet

echo "[deploy] rebuilding and starting services"
docker compose up -d --build

echo "[deploy] current service status"
docker compose ps

echo "[deploy] pruning dangling images"
docker image prune -f

echo "[deploy] done"