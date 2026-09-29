#!/usr/bin/env bash

set -euo pipefail

state="${IAM60_FAKE_STATE:-happy}"
printf '%s\n' "$*" >> "${IAM60_FAKE_LOG:?}"

if [[ "$1 $2" == "sts get-caller-identity" ]]; then
  if [[ "$*" == *"--query Arn"* ]]; then
    printf '%s\n' 'arn:aws:sts::111122223333:assumed-role/iam-60-lab-role/iam-60-lab-session'
  elif [[ "$state" == root* ]]; then
    printf '%s\n' '{"Account":"111122223333","Arn":"arn:aws:iam::111122223333:root"}'
  elif [[ "$state" == assumed* ]]; then
    printf '%s\n' '{"Account":"111122223333","Arn":"arn:aws:sts::111122223333:assumed-role/OperatorRole/session"}'
  elif [[ "$state" == unsupported* ]]; then
    printf '%s\n' '{"Account":"111122223333","Arn":"arn:aws:sts::111122223333:federated-user/Operator"}'
  else
    printf '%s\n' '{"Account":"111122223333","Arn":"arn:aws:iam::111122223333:user/Operator"}'
  fi
  exit 0
fi

if [[ "$1 $2" == "sts assume-role" ]]; then
  if [[ "$state" == "transient-assume" ]]; then
    assume_count="$(grep -c '^sts assume-role' "${IAM60_FAKE_LOG:?}")"
    if [[ "$assume_count" -lt 3 ]]; then
      printf '%s\n' 'AccessDenied: propagation delay' >&2
      exit 254
    fi
  fi
  printf '%s\t%s\t%s\n' 'ASIAFAKEACCESS' 'FAKESECRET' 'FAKESESSIONTOKEN'
  exit 0
fi

if [[ "$1 $2" == "accessanalyzer validate-policy" ]]; then
  printf '%s\n' '{"findings":[]}'
  exit 0
fi

if [[ "$1 $2" == "iam get-role" ]]; then
  if [[ "$*" == *"--role-name OperatorRole"* ]]; then
    printf '%s\n' 'arn:aws:iam::111122223333:role/team/OperatorRole'
    exit 0
  fi
  if [[ "$state" == *"before-create"* ]]; then
    printf '%s\n' 'NoSuchEntity' >&2
    exit 254
  fi
  if [[ "$state" == "after-delete" ]] || \
    grep -q '^iam delete-role ' "${IAM60_FAKE_LOG:?}"; then
    printf '%s\n' 'NoSuchEntity' >&2
    exit 254
  fi
  if [[ "$*" == *"--query Role.Arn"* ]]; then
    printf '%s\n' 'arn:aws:iam::111122223333:role/iam-60-lab-role'
  elif [[ "$*" == *"--query Role.RoleName"* ]]; then
    printf '%s\n' 'iam-60-lab-role'
  else
    printf '%s\n' '{"Role":{"RoleName":"iam-60-lab-role"}}'
  fi
  exit 0
fi

if [[ "$1 $2" == "iam list-role-tags" ]]; then
  if [[ "$state" == "tag-mismatch" ]]; then
    printf '%s\n' 'false'
  else
    printf '%s\n' 'true'
  fi
  exit 0
fi

if [[ "$1 $2" == "iam list-role-policies" ]]; then
  if [[ "$state" == "unexpected-inline" ]]; then
    printf '%s\n' 'iam-60-lab-policy OtherPolicy'
  elif [[ "$state" == "missing-inline" ]]; then
    printf '\n'
  else
    printf '%s\n' 'iam-60-lab-policy'
  fi
  exit 0
fi

if [[ "$1 $2" == "iam list-attached-role-policies" ]]; then
  if [[ "${AWS_ACCESS_KEY_ID:-}" == "ASIAFAKEACCESS" ]]; then
    printf '%s\n' 'AccessDenied' >&2
    exit 254
  fi
  if [[ "$state" == "unexpected-attached" ]]; then
    printf '%s\n' '1'
  else
    printf '%s\n' '0'
  fi
  exit 0
fi

case "$1 $2" in
  "iam create-role"|"iam put-role-policy"|"iam delete-role-policy"|"iam delete-role")
    exit 0
    ;;
esac

printf 'Unexpected fake AWS command: %s\n' "$*" >&2
exit 2
