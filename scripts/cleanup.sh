#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

iam60_require_tools

role_json=""
if ! role_json="$("$IAM60_AWS_CLI" iam get-role \
  --role-name "$IAM60_ROLE_NAME" --output json 2>&1)"; then
  if [[ "$role_json" == *"NoSuchEntity"* ]]; then
    printf '%s\n' 'The book-owned lab role is already absent.'
    exit 0
  fi
  iam60_die "Unable to inspect the lab role; cleanup stopped."
fi

owner_value="$("$IAM60_AWS_CLI" iam list-role-tags \
  --role-name "$IAM60_ROLE_NAME" \
  --query "Tags[?Key=='$IAM60_OWNER_KEY'].Value | [0]" \
  --output text)" || iam60_die "Unable to verify the ownership tag."
[[ "$owner_value" == "$IAM60_OWNER_VALUE" ]] || \
  iam60_die "The role is not marked as owned by this lab; cleanup stopped."

inline_names="$("$IAM60_AWS_CLI" iam list-role-policies \
  --role-name "$IAM60_ROLE_NAME" \
  --query 'PolicyNames' --output text)" || \
  iam60_die "Unable to inspect inline policies."
inline_policy_present="false"
case "$inline_names" in
  "$IAM60_POLICY_NAME") inline_policy_present="true" ;;
  ""|None) ;;
  *) iam60_die "The role has an unexpected inline-policy inventory; cleanup stopped." ;;
esac

attached_count="$("$IAM60_AWS_CLI" iam list-attached-role-policies \
  --role-name "$IAM60_ROLE_NAME" \
  --query 'length(AttachedPolicies)' --output text)" || \
  iam60_die "Unable to inspect attached policies."
[[ "$attached_count" == "0" ]] || \
  iam60_die "The role has an attached managed policy; cleanup stopped."

if [[ "$inline_policy_present" == "true" ]]; then
  "$IAM60_AWS_CLI" iam delete-role-policy \
    --role-name "$IAM60_ROLE_NAME" \
    --policy-name "$IAM60_POLICY_NAME"
fi
"$IAM60_AWS_CLI" iam delete-role --role-name "$IAM60_ROLE_NAME"

absence_output=""
absence_verified="false"
for ((attempt = 1; attempt <= IAM60_RETRY_ATTEMPTS; attempt++)); do
  if absence_output="$("$IAM60_AWS_CLI" iam get-role \
    --role-name "$IAM60_ROLE_NAME" 2>&1)"; then
    if ((attempt < IAM60_RETRY_ATTEMPTS)); then
      sleep "$IAM60_RETRY_DELAY_SECONDS"
    fi
    continue
  fi
  if [[ "$absence_output" == *"NoSuchEntity"* ]]; then
    absence_verified="true"
    break
  fi
  iam60_die "The role's absence could not be verified."
done
[[ "$absence_verified" == "true" ]] || \
  iam60_die "The lab role still exists after bounded cleanup checks."

unset role_json owner_value inline_names inline_policy_present attached_count
unset absence_output absence_verified attempt
printf '%s\n' 'Deleted the known inline policy and the tagged lab role.'
printf '%s\n' 'Verified that the book-owned role is absent.'
