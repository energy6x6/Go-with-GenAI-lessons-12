#!/usr/bin/env bash
# Підключення: source scripts/env.sh
# Налаштовує AWS CLI / SDK / Terraform на локальний Floci та визначає
# архітектуру, під яку треба збирати Lambda.

if [[ -n "${ZSH_VERSION:-}" ]]; then
  PROJECT_ROOT="$(cd "$(dirname "${(%):-%x}")/.." && pwd)"
else
  PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export PATH="$PROJECT_ROOT/.tools/bin:$PATH"
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  source "$PROJECT_ROOT/.env"
fi
export LESSON12_DOCKER_WRAPPER="${LESSON12_DOCKER_WRAPPER:-}"

export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export TF_VAR_floci_endpoint="$AWS_ENDPOINT_URL"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_REGION="$AWS_DEFAULT_REGION"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
unset AWS_SESSION_TOKEN AWS_SECURITY_TOKEN AWS_PROFILE
export AWS_EC2_METADATA_DISABLED=true
export SAM_CLI_TELEMETRY=0
export AWS_PAGER=""                       # не відкривати pager для виводу CLI

# ── Архітектура ────────────────────────────────────────────────────────────
# ВАЖЛИВО: Floci за замовчуванням запускає Lambda-контейнери в архітектурі
# Docker-хоста (FLOCI_SERVICES_LAMBDA_HONOUR_ARCHITECTURES=false). Тож бінарник
# має збігатися з хостом, інакше виклик впаде з «exec format error».
# Це та сама пастка, що на слайді 32: arm64 у Terraform ≠ збірка під amd64.
case "$(uname -m)" in
  arm64|aarch64) export GOARCH_LAMBDA=arm64 LAMBDA_ARCH=arm64 ;;
  *)             export GOARCH_LAMBDA=amd64 LAMBDA_ARCH=x86_64 ;;
esac
export TF_VAR_lambda_architecture="$LAMBDA_ARCH"
export LESSON12_RUNTIME_DIR="${LESSON12_RUNTIME_DIR:-$PROJECT_ROOT/../.lesson12-runtime}"
export LESSON12_EVIDENCE_DIR="${LESSON12_EVIDENCE_DIR:-$PROJECT_ROOT/../lesson12-evidence}"

# ── Імена ресурсів ─────────────────────────────────────────────────────────
export WEBHOOK_FN="libratrack-webhook"
export READER_FN="libratrack-reader"
export THUMB_FN="libratrack-thumbnail"
export COVERS_BUCKET="libratrack-covers"
export THUMBS_BUCKET="libratrack-thumbnails"
export ROLE_NAME="libratrack-lambda-role"
export API_NAME="libratrack-api"
export STAGE="dev"

# Обгортка: явний --endpoint-url працює навіть зі старим AWS CLI (< 2.13).
awsf() {
  case "$AWS_ENDPOINT_URL" in
    http://localhost:*|http://127.0.0.1:*) ;;
    *) echo "Only a local Floci endpoint is supported" >&2; return 1 ;;
  esac
  aws --endpoint-url "$AWS_ENDPOINT_URL" "$@"
}
