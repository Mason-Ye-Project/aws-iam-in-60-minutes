#!/usr/bin/env bash

set -euo pipefail
set +x

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

iam60_require_tools

role_arn="$(iam60_retry_capture "Reading the lab role" \
  "$IAM60_AWS_CLI" iam get-role \
  --role-name "$IAM60_ROLE_NAME" \
  --query 'Role.Arn' \
  --output text)"

owner_value="$("$IAM60_AWS_CLI" iam list-role-tags \
  --role-name "$IAM60_ROLE_NAME" \
  --query "Tags[?Key=='$IAM60_OWNER_KEY'].Value | [0]" \
  --output text)" || iam60_die "Unable to verify the ownership tag."
[[ "$owner_value" == "$IAM60_OWNER_VALUE" ]] || \
  iam60_die "The role is not marked as owned by this lab; execution stopped."

inline_names="$("$IAM60_AWS_CLI" iam list-role-policies \
  --role-name "$IAM60_ROLE_NAME" \
  --query 'PolicyNames' --output text)" || \
  iam60_die "Unable to inspect inline policies."
[[ "$inline_names" == "$IAM60_POLICY_NAME" ]] || \
  iam60_die "The role has an unexpected inline-policy inventory; execution stopped."

attached_count="$("$IAM60_AWS_CLI" iam list-attached-role-policies \
  --role-name "$IAM60_ROLE_NAME" \
  --query 'length(AttachedPolicies)' --output text)" || \
  iam60_die "Unable to inspect attached policies."
[[ "$attached_count" == "0" ]] || \
  iam60_die "The role has an attached managed policy; execution stopped."

(
  credential_line="$(iam60_retry_capture "Assuming the lab role" \
    "$IAM60_AWS_CLI" sts assume-role \
    --region "$IAM60_REGION" \
    --role-arn "$role_arn" \
    --role-session-name iam-60-lab-session \
    --duration-seconds 900 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)"
  read -r temp_access_key temp_secret_key temp_session_token <<< "$credential_line"
  unset credential_line
  [[ -n "$temp_access_key" && -n "$temp_secret_key" && -n "$temp_session_token" ]] || \
    iam60_die "Temporary credentials were not returned in the expected form."

  export AWS_ACCESS_KEY_ID="$temp_access_key"
  export AWS_SECRET_ACCESS_KEY="$temp_secret_key"
  export AWS_SESSION_TOKEN="$temp_session_token"

  assumed_arn="$("$IAM60_AWS_CLI" sts get-caller-identity \
    --region "$IAM60_REGION" --query 'Arn' --output text)" || \
    iam60_die "The temporary session could not identify itself."
  [[ "$assumed_arn" == arn:*:sts::*:assumed-role/"$IAM60_ROLE_NAME"/* ]] || \
    iam60_die "The temporary session is not the expected lab role."

  observed_role="$("$IAM60_AWS_CLI" iam get-role \
    --role-name "$IAM60_ROLE_NAME" \
    --query 'Role.RoleName' \
    --output text)" || iam60_die "The expected allowed request failed."
  [[ "$observed_role" == "$IAM60_ROLE_NAME" ]] || \
    iam60_die "The allowed request returned an unexpected role."

  denied_output=""
  if denied_output="$("$IAM60_AWS_CLI" iam list-attached-role-policies \
    --role-name "$IAM60_ROLE_NAME" 2>&1)"; then
    iam60_die "The read-only request expected to be denied was unexpectedly allowed."
  elif [[ "$denied_output" != *"AccessDenied"* ]]; then
    iam60_die "The read-only denied request failed for an unexpected reason."
  fi
  unset assumed_arn observed_role denied_output
  unset temp_access_key temp_secret_key temp_session_token
)

unset role_arn owner_value inline_names attached_count
printf '%s\n' 'Temporary identity confirmed: expected assumed-role shape for iam-60-lab-role.'
printf '%s\n' 'Temporary session confirmed: one exact-role read was allowed.'
printf '%s\n' 'A different read-only IAM request was denied by omission.'
printf '%s\n' 'Temporary credentials were held only inside this process and were not printed.'
