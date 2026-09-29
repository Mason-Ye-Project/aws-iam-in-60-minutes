# AWS IAM in 60 Minutes companion

This repository supports the bounded IAM role lifecycle in *AWS IAM in 60 Minutes* by Mason Ye.

The lab identifies the current non-root caller, creates one tagged role named `iam-60-lab-role`, validates and attaches one inline policy named `iam-60-lab-policy`, assumes the role for a 15-minute session, proves one allow and one implicit deny, then deletes the policy and role. IAM, ordinary STS calls, and IAM Access Analyzer policy validation carry no additional service charge; the lab creates no analyzer and calls no paid custom policy check.

## Prerequisites

- Bash
- `jq`
- AWS CLI v2
- an authenticated IAM user or assumed IAM role in an account where you are allowed to run the lab
- the permissions shown in `policies/reader-permissions-example.json`, adapted to your account ID and, for an assumed-role caller, the current caller role's path and name

The example permissions policy is documentation. The scripts do not attach policies to your current identity, create users or access keys, change passwords, or configure MFA. If you cannot grant the listed permissions, ask an administrator to prepare the lab identity.

If your prepared caller is an IAM user, remove the `ResolveTheCurrentCallerRoleWhenNeeded` statement. If your caller is already an assumed role, keep that statement and replace `<CURRENT_CALLER_ROLE_PATH_AND_NAME>` with the underlying IAM role path and name; the lab needs this one read to resolve the exact trust principal safely.

## Run the lab

The default STS and Access Analyzer Region is `ap-southeast-2`. Override it only if needed:

```bash
export IAM60_REGION=ap-southeast-2
```

Then run:

```bash
./scripts/create_lab.sh
./scripts/run_workflow.sh
./scripts/cleanup.sh
```

Run the local tests without contacting AWS:

```bash
./tests/test_shell_safety.sh
```

## Safety boundaries

- the scripts refuse an AWS account root caller and unsupported caller types;
- an assumed-role caller is resolved with `iam:GetRole`, so an IAM role path is never guessed from an STS session ARN;
- the role trust names one exact IAM user or IAM role ARN and never uses a wildcard or bare account principal;
- the permissions policy allows only `iam:GetRole` on the exact lab role;
- policy validation runs before the inline policy is attached and blocks on errors or security warnings;
- temporary credentials are created, parsed, exported, and consumed only inside one dedicated subshell; they are never printed or written to a credentials file;
- role execution and cleanup verify the exact ownership tag and refuse unexpected inline or attached policies;
- cleanup deletes only the known inline policy, if present, and the tagged lab role;
- cleanup verifies `NoSuchEntity` with bounded retries;
- retry loops are finite and never widen a policy in response to propagation delay.

The companion does not promise that deleting the role instantly revokes a previously issued STS session. The local credential environment disappears when the subshell exits, and the requested 900-second session expires naturally.

Code is licensed under 0BSD. The book prose is not included in that license.
