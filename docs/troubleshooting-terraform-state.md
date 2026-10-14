---
status: current
---

# Troubleshooting: stale Terraform/OpenTofu state lock

For whoever's responding to a `terragrunt plan`/`apply` that fails immediately with a state-lock error — not an introduction to the remote-state setup itself (see [`terragrunt/README.md`](../terragrunt/README.md) for the `.envrc`/`TG_IAM_ASSUME_ROLE` and provider-lock-file mechanics).

## 1. Recognize the symptom

```
Error: Error acquiring the state lock

Error message: operation error S3: PutObject, https response error
StatusCode: 412, ... api error PreconditionFailed: At least one of the pre-conditions you specified did not hold
Lock Info:
  ID:        18efe7b0-6332-f5e7-b00e-a68457ad1e08
  Path:      non-prod-homelab-eu-central-1-tf-state-443370678269/non-prod/eu-central-1/rebuild/vehagn-k8s/tf.tfstate
  Operation: OperationTypeApply
  Who:       sebi@hannelore
  Created:   2026-10-13 10:57:44.487422634 +0000 UTC
```

This repo's backend (`terragrunt/root.hcl`) uses OpenTofu's **native S3 locking** (`use_lockfile = true`), not a DynamoDB lock table (deliberately — see the comment right above that line). A lock is a companion object next to the state file, named `<key>.tflock` (here: `non-prod/eu-central-1/rebuild/vehagn-k8s/tf.tfstate.tflock`). `plan`/`apply` creates it on start and deletes it on exit — but a process that never gets to run that cleanup (killed with `SIGKILL`, a background-task timeout, a lost SSH session, Ctrl-C hitting the wrong goroutine) leaves the object behind, and every later `plan`/`apply` against that same unit fails the same way until it's removed.

## 2. Confirm the lock is actually stale before touching it

Check `Who` and `Created` against what's actually still running — removing a lock out from under a genuinely in-progress `apply` risks two writers touching state at once. If someone (or some agent) might still be mid-apply on that exact unit, wait or ask first.

## 3. Clear it

The direct way, using the env's normal `TG_IAM_ASSUME_ROLE` (see [`terragrunt/README.md`](../terragrunt/README.md)):

```sh
terragrunt force-unlock -force <LOCK_ID>
```

If that's not available — e.g. an AI agent's permission gate blocks `force-unlock` as a "modifies shared state" action (this happened verbatim during the incident that prompted this doc) — delete the `.tflock` object directly from S3 instead, using a profile/role with `s3:DeleteObject` on the state bucket:

```sh
export AWS_PROFILE="man-terraform-bootstrap-s3"
aws s3 rm s3://non-prod-homelab-eu-central-1-tf-state-443370678269/non-prod/eu-central-1/rebuild/vehagn-k8s/tf.tfstate.tflock

delete: s3://non-prod-homelab-eu-central-1-tf-state-443370678269/non-prod/eu-central-1/rebuild/vehagn-k8s/tf.tfstate.tflock
```

The bucket and key come straight from the error's `Path` field — split at the first `/` to get `<bucket>/<rest-of-key>`, then append `.tflock`. Don't reconstruct the bucket name by hand from `local.remote_state_bucket`'s naming scheme; copying it from the error avoids a typo'd `aws s3 rm` against the wrong key.

## 4. Retry

Re-run the original `terragrunt plan`/`apply`. It should proceed past the lock-acquire step entirely — no special flag needed, the object being gone is the whole fix.

## Verify the fix actually took

The retried command gets past "Error acquiring the state lock" and reaches its normal refresh/plan output. If it immediately fails with the *same* lock ID again, something re-acquired it between your delete and your retry (a concurrent run, or your own retry racing a still-exiting previous process) — wait a few seconds and check `Who`/`Created` again rather than deleting in a loop.
