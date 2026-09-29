#!/usr/bin/env bash

set -euo pipefail

real_aws="${IAM60_REAL_AWS_CLI:-aws}"
call_log="${IAM60_CALL_LOG:?Set IAM60_CALL_LOG to a private local log path.}"

# Record only the service and operation. Never record arguments, identifiers,
# policy documents, output, or credentials.
printf '%s\t%s %s\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  "${1:-missing-service}" \
  "${2:-missing-operation}" >> "$call_log"

exec "$real_aws" "$@"
