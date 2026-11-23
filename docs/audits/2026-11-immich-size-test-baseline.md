---
date: 2026-11-23
status: Baseline and test design only — the subset run, the remote machine learning comparison and the final recommendation for prod are still outstanding; they will be a later audit file
scope: the first measurements of Immich in qa (restart diagnosis, library composition, per-asset sizes and the one measured job rate), the design of the load and size test and a preliminary projection to the full library. It does not cover compute placement or prod sizing, which follow the test
origin: Claude (Claude Code), read-only access to the qa cluster (kubectl get, describe, top, logs, exec for cgroup files, du, find and SELECT queries). Nothing was changed on the cluster
tracking: https://github.com/isejalabs/homelab/issues/2147, related https://github.com/isejalabs/homelab/issues/2146, https://github.com/isejalabs/homelab/issues/2148 and https://github.com/isejalabs/homelab/issues/2149
---

# Immich size test, baseline in `qa` — 2026-11-23

## Result

- **The `qa` server restarts are memory-limit kills of its container.** 15 restarts in 12 hours, last state `OOMKilled` (exit 137), cgroup `memory.peak` equal to the 2 Gi limit. The API, the job worker and `ffmpeg` share one container; page-cache reclaim at the limit also made the 1 s liveness probe time out. Stop-gap: [PR #2455](https://github.com/isejalabs/homelab/pull/2455) (3 Gi, probe timeout 5 s). Details below.
- **The library is 111,375 assets and 1.95 TB** (38,658 RAW, 52,980 JPEG and similar, 15,095 HEIC, 4,642 videos). Videos are 4 % of the assets and 42 % of the bytes, RAW is a third of the assets. The phone upload set in `qa` (1,182 assets, 35 % video, no RAW) does not represent it.
- **Small items:** database about 19 KB per asset (about 3 GB for the full library), thumbnails and previews about 0.5 MB per asset (about 53 GB). Both fit the planned volumes by a wide margin.
- **Large uncertain items:** the encoded-video share of the cache dataset (between 0 and about 800 GB depending on the transcode policy), the time for RAW thumbnails and for the video transcodes of 4K sources, and the memory of the server container with such sources. The planned subset run measures exactly these.

## Method

Read-only, in the `immich` namespace of `qa` on 2026-11-23 between 07:00 and 08:30 local time:

- Restart diagnosis: `kubectl describe pod`, `get events`, `top pods --containers`, `top nodes`, `describe resourcequota`, logs of the previous and the current container, and in the server container `memory.current`, `memory.peak`, `memory.events`, `memory.stat`, `cpu.stat` and `/proc/<pid>/status`.
- Library composition: one `find` with `-printf` over the read-only library mount in the server pod, summed by top-level folder and class ([`data/2026-11-immich-library-composition.tsv`](data/2026-11-immich-library-composition.tsv), sizes in GB rounded). It took about two minutes of NFS metadata reads.
- Per-asset sizes: `SELECT` on the Immich database (`asset`, `asset_exif`, `asset_file`, `smart_search`, `face_search`, relation sizes), `du` and `find` on the cache dataset.
- Transcode rate: the timestamps of `Transcoding video` and `Successfully encoded` in the server log, joined with the file sizes and durations of the 18 clips.
- A sampler records every 30 s the `kubectl top` values, the server cgroup counters, the `ffmpeg` process count, restarts, the asset, smart-search and face counts and the database size. The raw samples go with the result audit.

## Restart diagnosis

| Observation | Value |
| --- | --- |
| Restarts of `immich-server` | 15 in 12 h |
| Last state | `OOMKilled`, exit 137, 34 s after an `ffmpeg` transcode started while face detection and thumbnails of uploads ran |
| Limits and requests | 1.5 CPU and 2 Gi; 250m and 768 Mi |
| `memory.peak` / `max` events since the last start | 2,147,475,456 bytes (the limit) / 90 |
| Memory at idle | anonymous 0.85 GiB (API process 0.29 GiB, job worker 0.64 GiB), page cache 0.8 GiB, working set 0.9–1.15 GiB |
| Before each kill | liveness and readiness probes `context deadline exceeded` (timeout 1 s), then `connection refused`, startup probe failures, `BackOff` |
| Node | no memory or disk pressure on `qa-work-03` (3.7 of 5.3 GiB allocatable in use), no eviction |
| Quota | memory limits 7,424 Mi of 9 Gi, requests 2,880 Mi of 4 Gi |
| Side effect | the upload jobs that run right after a start fail with `Machine learning repository not been setup` (face detection and OCR); 337 of 412 uploaded videos had no preview and 343 of 1,182 assets no smart-search vector |

The cause is the container limit, not the node and not the quota. A worker has 5.3 GiB allocatable and runs the server and the machine learning pod, so the limit cannot simply be raised far: the server needs a measured value and the worker size is a question for [#2148](https://github.com/isejalabs/homelab/issues/2148).

The stop-gap was merged and applied on 2026-11-23 ([PR #2455](https://github.com/isejalabs/homelab/pull/2455)): the limit is 3 Gi and the probe timeout 5 s, the new server pod started with 0 restarts. Side effect: the memory limits on `qa-work-03`, where the server and the machine learning pod run together, now add up to 161 % of the node's allocatable memory (8.7 of 5.4 GiB), so placing the two on different workers is part of the test design below.

## What the `qa` test set shows

n = 1,182 phone uploads (770 images, 412 videos, 7.8 GB). Extrapolation to 111,375 assets.

| Measure | Result | Projection |
| --- | --- | --- |
| Database, library tables with indexes and vectors (without 0.1 GB of geodata) | 22.1 MB, 18.7 KB per asset | about 2.1 GB, about 3 GB with all vectors and faces; 0.1–0.2 GB per year at 4,000–10,000 assets |
| Smart-search vectors, face vectors | 6.3 KB per asset, 6.2 KB per face | included above |
| Thumbnails and previews | 411 MB for 845 assets, 0.49 MB per asset | about 53 GB (range 40–70), 2.7 % of the originals |
| Encoded video | 70 of 412 videos transcoded (17 %), output 3,199 MB for 3,350 MB source | 0–800 GB, not extrapolable from this set |
| Transcode speed, 18 clips, 1080p about 30 fps, one job, 1.5 CPU | 0.9 s per MB of source, 1.35 s per second of video | 816 GB all transcoded about 8.5 days, 17 % about 1.4 days; 4K slower |

The 10–20 % of the Immich documentation does not apply to a library of large RAW files: previews have a fixed size, so the thumbnail share falls with the original size, and the encoded video share depends only on how many videos the policy transcodes.

## Library composition

| Class | Files | Size |
| --- | --- | --- |
| RAW (NEF, ARW, DNG, other) | 38,658 | 909 GB |
| JPEG, PNG, TIFF, BMP | 52,980 | 190 GB |
| HEIC | 15,095 | 32 GB |
| Video | 4,642 | 816 GB |
| Total | 111,375 | 1,947 GB |

About 54,500 `.xmp` sidecars come on top (not assets). One year (2023) has 443 videos with 466 GB, about 1 GB each.

## Test design

1. **Subset:** a second external library whose import path is the year 2022 (8,400 assets, 170 GB) plus a few 4K videos from 2023 as a separate import path. Database state, no repository change; deleted afterwards.
2. **Stages, one at a time:** scan and metadata, thumbnails, smart search and face detection, transcodes. Per stage: assets per minute, CPU and memory of the four workloads, `memory.peak` and `oom_kill`, cache growth, database size per 1,000 assets, Longhorn volume size, NFS load on `fiona`, load on the Proxmox host.
3. **Concurrency** first as committed, then raised one stage at a time through the settings file (a git change; the web UI is locked).
4. **More compute from the Proxmox hosts first, the Mac second.** The owner wants to try the path through the cluster before the Mac is used (the Mac is only free at night):
   - **Placement:** server and machine learning on different workers (now both on `qa-work-03`).
   - **Temporary bulk worker on `pve6`:** a fourth `qa` worker, sized large, tainted and excluded from Longhorn replica scheduling so that the volumes do not depend on a host that is normally off. It exists for the bulk import only; if the sizing shows that Immich and the other workloads need four nodes permanently, it becomes a permanent node.
   - **Parallel instances:** the documented split is one server container for the API and one for the job worker (`IMMICH_WORKERS_INCLUDE` and `IMMICH_WORKERS_EXCLUDE` set to `api`). More than one job-worker container and more than one machine learning replica behind one Service are not documented, so they are measured, not assumed.
   - **Remote machine learning on the Mac** (stock container, CPU only, port 3003, no authentication) comes after this, for the night, the in-cluster pod as fallback; the same 2,000 assets both ways.
5. **Extrapolation** from the rates per class and the class mix above.

The test does not start while the owner is testing uploads by hand. The server limit was raised to 3 Gi first (otherwise the first stage restarts the server again).

## Options researched

Six extended web searches (2026-11-23): remote machine learning on a Mac, `OOMKilled` and `ffmpeg` memory, import duration for 100,000 assets, database and cache size per asset, Intel iGPU with Proxmox, Talos and Immich, `ffmpeg` memory by resolution and concurrency.

- **Remote machine learning on a Mac:** the stock container works but without Metal or Core ML; a native service or a community project (not reviewed for maturity) would use Core ML. The ML service has no authentication, so a trusted network only. Several URLs are tried in order.
- **iGPU:** OpenVINO (ML) and Quick Sync (transcoding) are supported by Immich. On Talos on Proxmox the known path is PCI mapping with `vfio-pci`, the `i915` system extension and the Intel GPU device plugin ([jotavare/talos-homelab#34](https://redirect.github.com/jotavare/talos-homelab/issues/34)); SR-IOV transcodes but OpenVINO ML failed for one user ([immich-app/immich#19960](https://redirect.github.com/immich-app/immich/discussions/19960)); AV1 is decode only on Iris Xe. Worth the effort only if transcoding dominates after the test.
- **Duration anecdotes:** about 2.2 h per 10,000 photos on four cores (11 h per 50,000), older Xeons far slower, face detection the largest share. Consistent with one to several days for this library; replaced by measured rates.
- **Memory guidance:** Immich publishes only the 6 GB minimum for the whole stack, no per-container limit. A kill during a transcode can leave a corrupt encode ([immich-app/immich#27973](https://redirect.github.com/immich-app/immich/issues/27973)).
