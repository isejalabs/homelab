# RustFS bucket capacity check — implementation decision

**Date:** 2026-10-01. **Tracking:** [phase 1A, #1438](https://github.com/isejalabs/homelab/issues/1438). This is an implementation design based on read-only access; no RustFS or Checkmk configuration has been changed.

## Collection contract

On TrueNAS 25.10.0, RustFS `1.0.0-beta.12` serves `GET /rustfs/admin/v3/quota-stats/{bucket}`. All 12 known backup buckets returned quota and logical usage in 0.111–0.348 seconds on 2026-10-01. The result agrees with the existing ZFS dataset check at the aggregate level, while offering a per-bucket series. Keep this logical view separate from the existing physical ZFS dataset measurement.

The same route, response fields and bucket-scoped `s3:GetBucketQuota` authorization remain in the tagged RustFS 1.0.0 source. RustFS 1.0.0 was released 2026-09-16; TrueNAS currently runs the beta, so this source comparison does not authorize or require an upgrade. Validate against whichever app version is actually deployed at rollout.

Use the existing Checkmk `prod` site on monitoring2 (Checkmk 2.4.0p36 CRE) and a 15-minute collection interval. A successful reading supplies logical bytes, quota, free quota and percentage. Checkmk should retain these as per-bucket services with metric history and quota thresholds; use filesystem-style trend forecasting only if the selected Checkmk integration exposes the metrics to its native filesystem trend check. The custom collector must not claim a time-to-full value when the service has insufficient growth history, flat usage, or a negative trend.

The quota-stats payload has no per-bucket accounting timestamp. RustFS beta.12 scanner status did report a completed successful usage save and freshness window during a later observation, but `/rustfs/admin/v3/scanner/status` uses `admin:ServerInfo`. In this version that action also authorizes multiple unrelated sensitive information endpoints. Keep it off the initial monitoring identity. Treat failed quota-stat requests as UNKNOWN; do not turn failures into zero. Mark accounting age unknown until RustFS offers a narrower freshness permission or a separately reviewed broader read-only permission is accepted.

Each quota-stat request generates a warning-level RustFS admin event. Twelve buckets polled every 15 minutes produce up to 1,152 such records per day before retries. This is roughly 0.4% of the sampled 302k daily log lines, and should be checked against the SSD/write baseline once it completes. Avoid faster polling without a demonstrated need.

## Monitoring identity policy

The existing audit key is list-only, which is enough for listing bucket objects but not for this endpoint. Create a distinct monitoring identity with the bucket-only `s3:GetBucketQuota` policy in [the prepared policy JSON](data/2026-10-rustfs-checkmk-policy.json). Do not grant `ListBucket`, object read/write/delete, quota-setting actions or `admin:ServerInfo`.

RustFS beta.12 maps the same `s3:GetBucketQuota` action to bucket quota reads, quota statistics, and the quota-check endpoint. The latter computes whether a hypothetical operation would fit; it does not perform that object operation, though invoking it can trigger usage reads and warning/metric events. The policy is therefore bucket-scoped and object-read/write-free, but the API cannot constrain it to one HTTP path using this action alone.

Store the access key/secret in the Checkmk `prod` site's Password Store. Checkmk documents that the store encrypts/obfuscates the saved file with a key held in the same site directory, so site filesystem access remains trusted. The Checkmk 2.4 special-agent call must not place the secret in command-line arguments, which could expose it through process listings. The implementation must hand secret input over standard input or another protected mechanism and must keep it out of logs and diagnostics.

## Remaining work before live Checkmk collection

1. Owner creates the separate RustFS monitoring identity from the policy above and stores the secret in the `prod` Checkmk Password Store.
2. Implement and install the Checkmk 2.4-compatible custom API integration on monitoring2; add/configure the fiona host and discover stable per-bucket services manually in Checkmk.
3. Confirm the integration actually records quota metrics in Checkmk RRDs and gets useful native quota/time-to-full behavior. A metric graph alone does not satisfy the forecast requirement.
4. Verify the identity can query all 12 buckets and cannot access objects, alter quotas, or access unrelated admin endpoints. Confirm errors, deleted buckets, missing quotas and recovery produce explicit states.
5. Reconcile the first service values with the RustFS API and existing ZFS dataset check; set percentage and absolute reserve thresholds after reviewing real backup growth.
6. Recheck the added event/log and host-write rate at 15-minute cadence; keep polling at 15 minutes unless evidence supports changing it.

The Longhorn physical-disk checks remain a separate part of issue #1438 and can progress independently.
