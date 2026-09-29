#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

iam60_require_tools

existing_output=""
if existing_output="$("$IAM60_AWS_CLI" iam get-role \
  --role-name "$IAM60_ROLE_NAME" 2>&1)"; then
  iam60_die "The planned lab role already exists; nothing was changed."
elif [[ "$existing_output" != *"NoSuchEntity"* ]]; then
  iam60_die "The lab could not safely confirm that the planned role name is free."
fi
unset existing_output

principal_arn="$(iam60_resolve_principal_arn)"
read -r partition account_id < <(iam60_account_and_partition)
role_arn="arn:${partition}:iam::${account_id}:role/${IAM60_ROLE_NAME}"

work_dir="$(mktemp -d)"
cleanup_temp() {
  rm -f "$work_dir/trust-policy.json" "$work_dir/permissions-policy.json"
  rmdir "$work_dir" 2>/dev/null || true
}
trap cleanup_temp EXIT

jq -n --arg principal "$principal_arn" '{
  Version: "2012-10-17",
  Statement: [{
    Sid: "TrustOnePreparedPrincipal",
    Effect: "Allow",
    Principal: {AWS: $principal},
    Action: "sts:AssumeRole"
  }]
}' > "$work_dir/trust-policy.json"

jq -n --arg role_arn "$role_arn" '{
  Version: "2012-10-17",
  Statement: [{
    Sid: "InspectOnlyTheLabRole",
    Effect: "Allow",
    Action: "iam:GetRole",
    Resource: $role_arn
  }]
}' > "$work_dir/permissions-policy.json"

validation_json="$("$IAM60_AWS_CLI" accessanalyzer validate-policy \
  --region "$IAM60_REGION" \
  --policy-document "file://$work_dir/permissions-policy.json" \
  --policy-type IDENTITY_POLICY \
  --output json)" || iam60_die "Policy validation did not complete."

blocking_findings="$(printf '%s' "$validation_json" | jq '[
  .findings[]? | select(
    .findingType == "ERROR" or .findingType == "SECURITY_WARNING"
  )
] | length')"
[[ "$blocking_findings" == "0" ]] || \
  iam60_die "Policy validation returned a blocking finding; no role was created."

"$IAM60_AWS_CLI" iam create-role \
  --role-name "$IAM60_ROLE_NAME" \
  --description "Temporary role for AWS IAM in 60 Minutes" \
  --assume-role-policy-document "file://$work_dir/trust-policy.json" \
  --max-session-duration 3600 \
  --tags "Key=$IAM60_OWNER_KEY,Value=$IAM60_OWNER_VALUE" \
  >/dev/null

iam60_retry_capture "Attaching the lab policy" \
  "$IAM60_AWS_CLI" iam put-role-policy \
  --role-name "$IAM60_ROLE_NAME" \
  --policy-name "$IAM60_POLICY_NAME" \
  --policy-document "file://$work_dir/permissions-policy.json" \
  >/dev/null

printf '%s\n' 'Created the tagged lab role with one validated inline policy.'
printf '%s\n' 'No credentials or account-specific identifiers were printed.'
