#!/usr/bin/env bash
# Запускає Floci через Docker Compose та чекає готовності.
# Використання: scripts/up.sh [--ephemeral]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
if [[ -n "$LESSON12_DOCKER_WRAPPER" ]]; then
  echo "Floci uses a remote Docker host. Start this Compose file on that host, then use the forwarded AWS endpoint." >&2
  exit 1
fi

command -v docker >/dev/null || { echo "✗ Потрібен Docker"; exit 1; }
docker info >/dev/null 2>&1   || { echo "✗ Docker daemon не запущений"; exit 1; }

files=(-f compose.yaml)
if [[ "${1:-}" == "--ephemeral" ]]; then
  files+=(-f compose.ephemeral.yaml)
  echo "▶ Режим ephemeral: КОЖЕН виклик = холодний старт"
fi

echo "▶ Запускаю Floci…"
docker compose "${files[@]}" up -d

echo -n "▶ Чекаю на ${AWS_ENDPOINT_URL} "
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "${AWS_ENDPOINT_URL}/_floci/health" 2>/dev/null \
     || awsf s3 ls >/dev/null 2>&1; then
    echo " ✓"; break
  fi
  echo -n "."; sleep 1
done
awsf s3 ls >/dev/null 2>&1 || { echo; echo "✗ Floci не відповідає. Дивіться: docker compose logs floci"; exit 1; }

# Перший виклик Lambda тягне образ середовища (сотні МБ). Робимо це зараз,
# щоб на демо перший виклик не «зависав» (див. docs/TROUBLESHOOTING.md).
echo "▶ Завантажую образ середовища Lambda (provided.al2023)…"
docker pull public.ecr.aws/lambda/provided:al2023 >/dev/null 2>&1 \
  && echo "  ✓ готово" \
  || echo "  ⚠ не вдалося завантажити зараз — Floci спробує під час першого виклику"
