#!/usr/bin/env bash
# Local Floci only. Review the saved plan before applying it.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
TF=$(command -v terraform || command -v tofu) || { echo "Terraform or OpenTofu is required" >&2; exit 1; }
mkdir -p "$LESSON12_RUNTIME_DIR"
RUNTIME=$(cd "$LESSON12_RUNTIME_DIR" && pwd)
PLAN="$RUNTIME/terraform.plan"
for fn in webhook thumbnail reader; do
  [[ -f "build/$fn.zip" ]] || { echo "Run make build first" >&2; exit 1; }
done
mode=${1:-plan}
case "$mode" in plan|apply|destroy) ;; *) echo "Expected plan, apply or destroy" >&2; exit 1 ;; esac
"$TF" -chdir=terraform init -input=false -backend-config="path=$RUNTIME/terraform.tfstate"
"$TF" -chdir=terraform validate
case "$mode" in
  plan)
    "$TF" -chdir=terraform plan -input=false -out="$PLAN"
    echo "Review: terraform -chdir=terraform show $PLAN"
    ;;
  apply)
    [[ -f "$PLAN" ]] || { echo "Run make plan-tf and review the plan first" >&2; exit 1; }
    "$TF" -chdir=terraform apply -input=false "$PLAN"
    "$TF" -chdir=terraform output
    ;;
  destroy)
    "$TF" -chdir=terraform destroy
    ;;
esac
