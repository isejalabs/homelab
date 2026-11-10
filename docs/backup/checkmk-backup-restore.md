---
status: current
---

# Checkmk Site Backup & Restore

| Row | |
| --- | --- |
| When to use | Proving a Checkmk site's own backup (`omd backup`) is actually recoverable — a full site restore, not application data or a VM/LXC. For the container's root filesystem itself, see [`proxmox-backup-restore.md`](proxmox-backup-restore.md); the owner accepts PBS restores of CT 7002056 as proven by other guests ([#2157](https://github.com/isejalabs/homelab/issues/2157)), so this doc only covers the site-level backup. |
| Prerequisites | Root SSH to the Checkmk container (`monitoring1`/`monitoring2`); enough free root-disk space for a second copy of the site (`omd backup` is roughly the site's own `du -sh`, see [`monitoring-sites.md`](../reference/monitoring-sites.md)); `unshare`/`nsenter` available (standard on these containers). |
| Steps | [Restore into an isolated site](#restore-into-an-isolated-site) below. |
| Verify | [Open old graphs through the REST API](#open-old-graphs) — confirms the restored RRDs and Livestatus config resolve correctly. |
| Rollback | Not applicable: the restore creates a new, separate site next to the live ones. Delete it when done ([Tear down](#tear-down)); the live sites are never touched. |
| Last exercised | 2026-11-10, on `monitoring2`: `prod`'s backup restored into a throwaway site `restoretest`, 30 days of real `fs_used` history for `monitoring1.home.iseja.net` `Filesystem /` read back through the Checkmk REST API. Torn down the same session. |

## Why isolate the restore

A restored site starts as an exact copy of the source site's configuration — same hosts, same checks, same notification rules. If it is simply started normally, it immediately begins running active checks against the real network and, depending on the source site's notification settings, can send real notifications. Stream A's acceptance criteria require the restore to be "safe/non-disruptive" and never touch the live `prod`/`prod_k8s` sites — so the whole site runs inside a separate Linux network namespace (`unshare -n`) with nothing but loopback, for the entire time it exists.

> [!CAUTION]
> Do not start a restored site in the host's normal network namespace. It carries the same host/check/notification configuration as the site it was copied from and will poll real devices and can send real notifications the moment it starts.

## Restore into an isolated site

1. **Stream the backup straight into the restore** — no intermediate backup file touches disk:

   ```sh
   omd backup <source-site> - | /omd/versions/<version>/bin/omd restore --apache-reload <new-site> -
   ```

   > [!WARNING]
   > If the container's *default* `omd` binary is a different edition/version than the source site (e.g. the container also hosts an Ultimate site and `omd` resolves to that version), restoring through the bare `omd` command fails with `Failed to open the backup: invalid header` — the restore re-execs into the other edition's binary partway through consuming stdin, corrupting the stream. Call the matching version's binary directly (`/omd/versions/<version>/bin/omd restore ...`), found from `omd sites` or the source site's `etc/omd/site.conf`.

2. **Change the new site's web port** if the restored `site.conf` collides with another running site on the same container (the restore keeps the source site's port) — `omd config set APACHE_TCP_PORT <free-port>`; `omd` auto-picks the next free one and warns if you don't.

3. **Reset the admin password** rather than trying to recover the original — the hash is copied from the backup and its plaintext is not known:

   ```sh
   echo '<temporary-password>' | su - <new-site> -c 'cmk-passwd --stdin cmkadmin'
   ```

4. **Start the whole site inside an isolated network namespace**, with only loopback up:

   ```sh
   cat >/root/<new-site>-start.sh <<'EOF'
   #!/bin/sh
   set -e
   ip link set lo up
   exec su - <new-site> -c "omd start"
   EOF
   chmod +x /root/<new-site>-start.sh
   setsid unshare -n /root/<new-site>-start.sh </dev/null >/root/<new-site>-start.log 2>&1 &
   disown
   ```

5. **Watch for namespace drift while the site runs.** In the 2026-11-10 drill, every long-running process started inside the namespace stayed there except Apache, which came back up in the host's default namespace once RabbitMQ (the message broker used for distributed monitoring/piggyback) finished its own startup — the root cause wasn't pinned down in the time available. A watchdog loop killed anything that drifted:

   ```sh
   cat >/root/<new-site>-netns-watchdog.sh <<'EOF'
   #!/bin/sh
   ISOLATED=<isolated-netns-inode>   # readlink /proc/<any-pid-known-isolated>/ns/net
   while true; do
     for p in $(pgrep -u <new-site> 2>/dev/null); do
       ns=$(readlink /proc/$p/ns/net 2>/dev/null)
       if [ -n "$ns" ] && [ "$ns" != "net:[$ISOLATED]" ]; then
         echo "$(date -u +%FT%TZ) DRIFT pid=$p ns=$ns cmd=$(ps -o args= -p $p 2>/dev/null)" >>/root/<new-site>-netns-drift.log
         kill -9 "$p" 2>/dev/null
       fi
     done
     sleep 2
   done
   EOF
   chmod +x /root/<new-site>-netns-watchdog.sh
   setsid /root/<new-site>-netns-watchdog.sh </dev/null >/root/<new-site>-netns-watchdog.log 2>&1 &
   disown
   ```

   If Apache does drift out, stop it (`su - <new-site> -c "omd stop apache"`) and restart it explicitly inside the namespace: `nsenter -t <pid-known-isolated> -n setsid su - <new-site> -c "omd start apache"`. Re-check every process's namespace (`for p in $(pgrep -u <new-site>); do readlink /proc/$p/ns/net; done`) before trusting the isolation again. This drift was read-only in the one case caught (a self-monitoring `omd status --bare` probe from the host), but treat any drift as a stop-and-recheck signal, not a non-event.

## Open old graphs

Reach the isolated site's Apache (bound to loopback inside its own namespace) with `nsenter -t <any-pid-in-that-namespace> -n curl ...`. Log in with a cookie session using the temporary password from step 3, then confirm the restored config/data resolve correctly — either by loading a `service_graphs` view (its title/breadcrumb comes from the restored Livestatus config) or, more conclusively, by pulling the actual historical metric data through the REST API with the site's own `automation` user secret (`var/check_mk/web/automation/automation.secret`, read server-side only — never print or copy it off the host):

```sh
SECRET=$(cat /omd/sites/<new-site>/var/check_mk/web/automation/automation.secret)
curl -s -H "Authorization: Bearer automation $SECRET" -H "Accept: application/json" \
  -X POST http://127.0.0.1:<port>/<new-site>/check_mk/api/1.0/domain-types/metric/actions/get/invoke \
  -H "Content-Type: application/json" \
  -d '{"type":"single_metric","time_range":{"start":"<ISO-8601>","end":"<ISO-8601>"},"host_name":"<host>","service_description":"<service>","metric_id":"<metric>"}'
```

A `200` with real `data_points` is the proof: it is the same RRD data the browser-rendered graph would show, served through the same authenticated site, confirming the RRDs and the Livestatus/WATO config survived the restore. The 2026-11-10 drill pulled 30 days of `fs_used` for `monitoring1.home.iseja.net` `Filesystem /` from a `prod` backup restored as `restoretest`, matching the values read directly off the live RRDs beforehand.

A full pixel-rendered screenshot (the literal browser view) needs either an SSH port-forward relayed into the isolated namespace (`nsenter ... socat TCP-LISTEN:<port>,fork TCP:127.0.0.1:<site-port>` bridged to an SSH `-L` tunnel) or a browser running on the container itself; not done in the 2026-11-10 drill since the REST API evidence was conclusive on its own.

## Tear down

Stop and remove the site, then clean up every scratch file created on the host:

```sh
pkill -f <new-site>-netns-watchdog.sh
su - <new-site> -c "omd stop"
omd -f rm --apache-reload <new-site>
rm -f /root/<new-site>-*.sh /root/<new-site>-*.log
```

Verify the container's root filesystem usage returned to its pre-restore baseline (`df -m /`) — the restored site's data (comparable in size to the source site, see [`monitoring-sites.md`](../reference/monitoring-sites.md)) is reclaimed once `omd -f rm` completes.
