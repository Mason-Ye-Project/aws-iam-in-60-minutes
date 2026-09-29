#!/usr/bin/env bash

set -euo pipefail

IAM60_AWS_CLI="${IAM60_AWS_CLI:-aws}"
IAM60_REGION="${IAM60_REGION:-${AWS_REGION:-ap-southeast-2}}"
IAM60_ROLE_NAME="${IAM60_ROLE_NAME:-iam-60-lab-role}"
IAM60_POLICY_NAME="${IAM60_POLICY_NAME:-iam-60-lab-policy}"
IAM60_OWNER_KEY="iam-60-lab"
IAM60_OWNER_VALUE="true"
IAM60_RETRY_ATTEMPTS="${IAM60_RETRY_ATTEMPTS:-5}"
IAM60_RETRY_DELAY_SECONDS="${IAM60_RETRY_DELAY_SECONDS:-2}"

iam60_die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

iam60_require_tools() {
  command -v "$IAM60_AWS_CLI" >/dev/null 2>&1 || \
    iam60_die "AWS CLI is not available."
  command -v jq >/dev/null 2>&1 || iam60_die "jq is not available."
  [[ "$IAM60_RETRY_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || \
    iam60_die "IAM60_RETRY_ATTEMPTS must be a positive integer."
  [[ "$IAM60_RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] || \
    iam60_die "IAM60_RETRY_DELAY_SECONDS must be a non-negative integer."
}

iam60_retry_capture() {
  local label="$1"
  shift
  local attempt output

  for ((attempt = 1; attempt <= IAM60_RETRY_ATTEMPTS; attempt++)); do
    if output="$("$@" 2>&1)"; then
      printf '%s' "$output"
      return 0
    fi
    if ((attempt < IAM60_RETRY_ATTEMPTS)); then
      sleep "$IAM60_RETRY_DELAY_SECONDS"
    fi
  done

  unset output
  iam60_die "$label did not succeed after bounded retries."
}

iam60_caller_json() {
  "$IAM60_AWS_CLI" sts get-caller-identity \
    --region "$IAM60_REGION" --output json
}

iam60_resolve_principal_arn() {
  local caller_json caller_arn role_name principal_arn

  caller_json="$(iam60_caller_json)" || \
    iam60_die "Unable to identify the current AWS caller."
  caller_arn="$(printf '%s' "$caller_json" | jq -r '.Arn // empty')"

  case "$caller_arn" in
    arn:*:iam::*:root)
      iam60_die "The root user must not run this lab."
      ;;
    arn:*:iam::*:user/*)
      printf '%s\n' "$caller_arn"
      ;;
    arn:*:sts::*:assumed-role/*)
      role_name="${caller_arn#*:assumed-role/}"
      role_name="${role_name%%/*}"
      [[ -n "$role_name" ]] || \
        iam60_die "Unable to identify the underlying IAM role."
      principal_arn="$("$IAM60_AWS_CLI" iam get-role \
        --role-name "$role_name" \
        --query 'Role.Arn' \
        --output text)" || \
        iam60_die "Unable to resolve the underlying IAM role."
      [[ "$principal_arn" == arn:*:iam::*:role/* ]] || \
        iam60_die "The resolved principal is not an IAM role."
      printf '%s\n' "$principal_arn"
      ;;
    *)
      iam60_die "This caller type is not supported by the lab."
      ;;
  esac
}

iam60_account_and_partition() {
  local caller_json caller_arn account_id partition
  caller_json="$(iam60_caller_json)" || \
    iam60_die "Unable to identify the current AWS caller."
  caller_arn="$(printf '%s' "$caller_json" | jq -r '.Arn // empty')"
  account_id="$(printf '%s' "$caller_json" | jq -r '.Account // empty')"
  partition="${caller_arn#arn:}"
  partition="${partition%%:*}"
  [[ "$account_id" =~ ^[0-9]{12}$ ]] || \
    iam60_die "The caller account identifier is not in the expected form."
  [[ -n "$partition" ]] || iam60_die "Unable to determine the AWS partition."
  printf '%s\t%s\n' "$partition" "$account_id"
}
