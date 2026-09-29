#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fake_aws="$project_dir/tests/fake_aws.sh"
test_dir="$(mktemp -d)"
trap 'rm -f "$test_dir"/*; rmdir "$test_dir"' EXIT

chmod +x "$fake_aws" "$project_dir"/scripts/*.sh

run_with_state() {
  local state="$1"
  shift
  IAM60_AWS_CLI="$fake_aws" \
  IAM60_FAKE_STATE="$state" \
  IAM60_FAKE_LOG="$test_dir/commands.log" \
    "$@"
}

: > "$test_dir/commands.log"
if run_with_state root-before-create "$project_dir/scripts/create_lab.sh" \
  >"$test_dir/root.out" 2>"$test_dir/root.err"; then
  printf '%s\n' 'root refusal test unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'root user must not run' "$test_dir/root.err"
! grep -q 'iam create-role' "$test_dir/commands.log"

: > "$test_dir/commands.log"
run_with_state assumed bash -c \
  "source '$project_dir/scripts/common.sh'; iam60_resolve_principal_arn" \
  > "$test_dir/assumed.out"
grep -q 'role/team/OperatorRole' "$test_dir/assumed.out"

: > "$test_dir/commands.log"
if run_with_state unsupported-before-create "$project_dir/scripts/create_lab.sh" \
  >"$test_dir/unsupported.out" 2>"$test_dir/unsupported.err"; then
  printf '%s\n' 'unsupported-principal test unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'caller type is not supported' "$test_dir/unsupported.err"
! grep -q 'iam create-role' "$test_dir/commands.log"

: > "$test_dir/commands.log"
if run_with_state happy "$project_dir/scripts/create_lab.sh" \
  >"$test_dir/existing.out" 2>"$test_dir/existing.err"; then
  printf '%s\n' 'pre-existing-role test unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'planned lab role already exists' "$test_dir/existing.err"
! grep -q 'iam create-role' "$test_dir/commands.log"

: > "$test_dir/commands.log"
run_with_state user-before-create "$project_dir/scripts/create_lab.sh" \
  > "$test_dir/create.out"
grep -q 'Created the tagged lab role' "$test_dir/create.out"
grep -q 'accessanalyzer validate-policy' "$test_dir/commands.log"
grep -q 'iam create-role' "$test_dir/commands.log"
grep -q 'iam put-role-policy' "$test_dir/commands.log"
validate_line="$(grep -n 'accessanalyzer validate-policy' "$test_dir/commands.log" | cut -d: -f1)"
create_line="$(grep -n 'iam create-role' "$test_dir/commands.log" | cut -d: -f1)"
[[ "$validate_line" -lt "$create_line" ]]

: > "$test_dir/commands.log"
run_with_state happy "$project_dir/scripts/run_workflow.sh" \
  > "$test_dir/workflow.out"
grep -q 'one exact-role read was allowed' "$test_dir/workflow.out"
grep -q 'denied by omission' "$test_dir/workflow.out"
! grep -Eq 'ASIAFAKEACCESS|FAKESECRET|FAKESESSIONTOKEN' "$test_dir/workflow.out"

: > "$test_dir/commands.log"
IAM60_RETRY_ATTEMPTS=3 IAM60_RETRY_DELAY_SECONDS=0 \
  run_with_state transient-assume "$project_dir/scripts/run_workflow.sh" \
  > "$test_dir/retry.out"
[[ "$(grep -c '^sts assume-role' "$test_dir/commands.log")" == "3" ]]
! grep -Eq 'ASIAFAKEACCESS|FAKESECRET|FAKESESSIONTOKEN' "$test_dir/retry.out"

: > "$test_dir/commands.log"
if run_with_state tag-mismatch "$project_dir/scripts/run_workflow.sh" \
  >"$test_dir/tag.out" 2>"$test_dir/tag.err"; then
  printf '%s\n' 'tag-mismatch test unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'not marked as owned' "$test_dir/tag.err"
! grep -q '^sts assume-role' "$test_dir/commands.log"

: > "$test_dir/commands.log"
if run_with_state unexpected-attached "$project_dir/scripts/cleanup.sh" \
  >"$test_dir/attached.out" 2>"$test_dir/attached.err"; then
  printf '%s\n' 'unexpected attached-policy test unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'attached managed policy' "$test_dir/attached.err"
! grep -q 'iam delete-role ' "$test_dir/commands.log"

: > "$test_dir/commands.log"
if run_with_state unexpected-inline "$project_dir/scripts/cleanup.sh" \
  >"$test_dir/inline.out" 2>"$test_dir/inline.err"; then
  printf '%s\n' 'unexpected-inline-policy test unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'unexpected inline-policy inventory' "$test_dir/inline.err"
! grep -q 'iam delete-role ' "$test_dir/commands.log"

: > "$test_dir/commands.log"
run_with_state happy "$project_dir/scripts/cleanup.sh" \
  > "$test_dir/cleanup.out"
grep -q 'Verified that the book-owned role is absent' "$test_dir/cleanup.out"
grep -q '^iam delete-role-policy ' "$test_dir/commands.log"
grep -q '^iam delete-role ' "$test_dir/commands.log"

: > "$test_dir/commands.log"
run_with_state missing-inline "$project_dir/scripts/cleanup.sh" \
  > "$test_dir/cleanup-missing-inline.out"
grep -q 'Verified that the book-owned role is absent' "$test_dir/cleanup-missing-inline.out"
! grep -q '^iam delete-role-policy ' "$test_dir/commands.log"
grep -q '^iam delete-role ' "$test_dir/commands.log"

for script in "$project_dir"/scripts/*.sh "$project_dir"/tests/*.sh; do
  bash -n "$script"
done

printf '%s\n' 'IAM companion tests: PASS'
