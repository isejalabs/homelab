#!/usr/bin/env python3
"""Per-command CPU profile of one LXC container, run on its Proxmox host.

Why not BSD process accounting (acct): it stores CPU time in 10 ms ticks, so
the thousands of short checks (check_icmp, forks of the Nagios core) of a
monitoring site would mostly round to zero. Why not pidstat/atop: not
installed on the hosts, and a sampler misses processes that live for a few
milliseconds.

How: a taskstats listener (generic netlink, the interface behind the
kernel's getdelays tool) receives one record per exiting task with its exact
CPU time (ns). A /proc scanner every SCAN_INTERVAL seconds remembers the
cgroup, uid and command line of each process it sees (the exit record only
has the 15-character comm, and every Checkmk precompiled host check is
"python3"), and samples the CPU time of long-lived processes so daemons that
never exit are counted as well. Tasks that exit before the scanner sees them
are attributed through their parent; what still cannot be attributed is
counted as "unattributed". The container cgroup's own cpu.stat is recorded
too, so the coverage of the profile can be checked.

Nothing is written but one JSON summary per hour into OUT_DIR (a few hundred
kB a day). Stop it with SIGTERM; it writes the partial hour first.

Usage: ct-cpu-profile.py <vmid> <out-dir> [hours]
"""

import json
import os
import signal
import socket
import struct
import sys
import threading
import time
from collections import defaultdict

SCAN_INTERVAL = 0.25
NETLINK_GENERIC = 16
GENL_ID_CTRL = 0x10
CTRL_CMD_GETFAMILY = 3
CTRL_ATTR_FAMILY_ID = 1
CTRL_ATTR_FAMILY_NAME = 2
TASKSTATS_CMD_GET = 1
TASKSTATS_CMD_NEW = 2
TASKSTATS_CMD_ATTR_REGISTER_CPUMASK = 3
TASKSTATS_TYPE_PID = 1
TASKSTATS_TYPE_STATS = 3
TASKSTATS_TYPE_AGGR_PID = 4
CLK_TCK = os.sysconf("SC_CLK_TCK")

VMID = sys.argv[1]
OUT_DIR = sys.argv[2]
HOURS = float(sys.argv[3]) if len(sys.argv) > 3 else 25
CG_MARK = f"/lxc/{VMID}/"
CG_STAT = f"/sys/fs/cgroup/lxc/{VMID}/cpu.stat"

lock = threading.Lock()
# pid -> dict(start, inct, uid, key, cpu_seen); filled by the scanner
procs = {}
# (uid, key) -> [count, cpu_ns, utime_us, stime_us]
exited = defaultdict(lambda: [0, 0, 0, 0])
# (uid, key) -> cpu_ns sampled from processes that were alive
alive = defaultdict(int)
counters = defaultdict(int)
stop = threading.Event()


def read(path):
    with open(path, "rb") as f:
        return f.read()


def uid_names():
    """uid -> user name inside the container (its /etc/passwd)."""
    names = {}
    try:
        root = f"/proc/{lxc_init_pid()}/root/etc/passwd"
        for line in read(root).decode().splitlines():
            parts = line.split(":")
            names[int(parts[2])] = parts[0]
    except (OSError, ValueError, IndexError):
        pass
    return names


def lxc_init_pid():
    for line in read(f"/sys/fs/cgroup/lxc/{VMID}/ns/init.scope/cgroup.procs").split():
        return int(line)
    raise RuntimeError("container not running")


def classify(argv, comm):
    """A stable, short key for a command line."""
    if not argv:
        return comm
    exe = os.path.basename(argv[0])
    args = argv[1:]
    if exe.startswith("python"):
        rest = [a for a in args if not a.startswith("-")]
        if rest:
            script = rest[0]
            if "/host_checks/" in script:
                return "hostcheck " + os.path.basename(script)
            exe = os.path.basename(script)
            args = rest[1:]
    if exe in ("sh", "bash", "dash") and len(args) >= 2 and args[0] == "-c":
        return "sh -c " + args[1].split()[0].rsplit("/", 1)[-1]
    if exe.startswith("agent_") or exe.startswith("check_"):
        # special agents and active checks: keep the first host-like argument
        host = next((a for a in args if "." in a and not a.startswith("-") and "/" not in a), "")
        return f"{exe} {host}".strip()
    return exe


def proc_info(pid):
    """(start, in_container, uid, key, cpu_ns) of a live pid, or None."""
    try:
        stat = read(f"/proc/{pid}/stat").decode()
        rparen = stat.rindex(")")
        comm = stat[stat.index("(") + 1:rparen]
        fields = stat[rparen + 2:].split()
        start = int(fields[19])
        cpu = (int(fields[11]) + int(fields[12])) * 1_000_000_000 // CLK_TCK
        cg = read(f"/proc/{pid}/cgroup").decode()
        inct = CG_MARK in cg
        if not inct:
            return start, False, None, None, cpu
        uid = int(read(f"/proc/{pid}/status").decode().split("\nUid:\t", 1)[1].split()[0])
        argv = [a.decode(errors="replace") for a in read(f"/proc/{pid}/cmdline").split(b"\0") if a]
        return start, True, uid, classify(argv, comm), cpu
    except (OSError, ValueError, IndexError):
        return None


def scanner():
    while not stop.is_set():
        seen = set()
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            pid = int(name)
            seen.add(pid)
            with lock:
                known = procs.get(pid)
            if known is not None and not known["inct"]:
                continue
            if known is not None:
                # alive container process: account the CPU it used since the last sample
                try:
                    fields = read(f"/proc/{pid}/stat").decode().rsplit(")", 1)[1].split()
                    if int(fields[19]) == known["start"]:
                        cpu = (int(fields[11]) + int(fields[12])) * 1_000_000_000 // CLK_TCK
                        with lock:
                            if cpu > known["cpu_seen"]:
                                alive[(known["uid"], known["key"])] += cpu - known["cpu_seen"]
                                known["cpu_seen"] = cpu
                        continue
                except (OSError, ValueError, IndexError):
                    continue
            info = proc_info(pid)
            if info is None:
                continue
            start, inct, uid, key, cpu = info
            with lock:
                procs[pid] = {"start": start, "inct": inct, "uid": uid, "key": key,
                              # CPU used before the first sample counts too, except for
                              # processes that were already running when the profile started
                              "cpu_seen": cpu if counters["scans"] == 0 else 0}
        with lock:
            counters["scans"] += 1
            # forget pids that are gone and were not reaped by an exit record
            for pid in [p for p in procs if p not in seen and procs[p].get("gone")]:
                del procs[pid]
            for pid, info in procs.items():
                if pid in seen:
                    info.pop("gone", None)
                else:
                    info["gone"] = True
        stop.wait(SCAN_INTERVAL)


def nla(attr_type, payload):
    length = 4 + len(payload)
    return struct.pack("HH", length, attr_type) + payload + b"\0" * ((4 - length % 4) % 4)


def parse_attrs(buf):
    out = []
    i = 0
    while i + 4 <= len(buf):
        length, attr_type = struct.unpack_from("HH", buf, i)
        if length < 4:
            break
        out.append((attr_type & 0x3FFF, buf[i + 4:i + length]))
        i += (length + 3) & ~3
    return out


def genl_msg(family, cmd, attrs, seq):
    payload = struct.pack("BBH", cmd, 1, 0) + attrs
    return struct.pack("IHHII", 16 + len(payload), family, 1, seq, 0) + payload


def open_taskstats():
    sock = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, NETLINK_GENERIC)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
    sock.bind((0, 0))
    sock.send(genl_msg(GENL_ID_CTRL, CTRL_CMD_GETFAMILY, nla(CTRL_ATTR_FAMILY_NAME, b"TASKSTATS\0"), 1))
    reply = sock.recv(65536)
    family = None
    for attr_type, payload in parse_attrs(reply[20:]):
        if attr_type == CTRL_ATTR_FAMILY_ID:
            family = struct.unpack("H", payload[:2])[0]
    if family is None:
        raise RuntimeError("TASKSTATS family not found")
    ncpu = os.cpu_count()
    mask = f"0-{ncpu - 1}\0".encode()
    sock.send(genl_msg(family, TASKSTATS_CMD_GET, nla(TASKSTATS_CMD_ATTR_REGISTER_CPUMASK, mask), 2))
    return sock


def on_exit(stats):
    # struct taskstats (linux/taskstats.h): cpu_run_real_total at 64 (ns),
    # ac_comm at 80, ac_uid/gid/pid/ppid at 120, ac_utime/ac_stime at 152 (us)
    cpu_ns = struct.unpack_from("Q", stats, 64)[0]
    comm = stats[80:112].split(b"\0", 1)[0].decode(errors="replace")
    uid, _gid, pid, ppid = struct.unpack_from("IIII", stats, 120)
    utime, stime = struct.unpack_from("QQ", stats, 152)
    with lock:
        info = procs.pop(pid, None)
        if info is not None and not info["inct"]:
            return
        if info is not None:
            # the part already counted by the scanner is not counted twice
            key = (info["uid"], info["key"])
            exited[key][0] += 1
            exited[key][1] += max(cpu_ns - info["cpu_seen"], 0)
            exited[key][2] += utime
            exited[key][3] += stime
            return
        parent = procs.get(ppid)
    if parent is None:
        # parent not known yet (both short-lived): ask the kernel while it still exists
        pinfo = proc_info(ppid)
        if pinfo is not None:
            with lock:
                parent = procs.setdefault(ppid, {"start": pinfo[0], "inct": pinfo[1], "uid": pinfo[2],
                                                 "key": pinfo[3], "cpu_seen": 0})
    with lock:
        if parent is not None and not parent["inct"]:
            counters["host_exits"] += 1
            return
        if parent is not None:
            key = (uid, f"{comm} <- {parent['key']}")
        else:
            key = (uid, f"{comm} <- ?")
            counters["unattributed_exits"] += 1
            counters["unattributed_ns"] += cpu_ns
            # only a tiny share is expected; host tasks also land here, so this
            # stays separate from the container's ranking
            exited[("?", key[1])][0] += 1
            exited[("?", key[1])][1] += cpu_ns
            return
        exited[key][0] += 1
        exited[key][1] += cpu_ns
        exited[key][2] += utime
        exited[key][3] += stime


def listener(sock):
    sock.settimeout(1.0)
    while not stop.is_set():
        try:
            data = sock.recv(1 << 20)
        except socket.timeout:
            continue
        except OSError as err:
            # ENOBUFS: the kernel dropped records because we were too slow
            with lock:
                counters["recv_errors"] += 1
                counters["last_error"] = str(err)
            continue
        i = 0
        while i + 16 <= len(data):
            length = struct.unpack_from("I", data, i)[0]
            if length < 16:
                break
            msg = data[i + 16:i + length]
            i += (length + 3) & ~3
            if not msg or msg[0] != TASKSTATS_CMD_NEW:
                continue
            for attr_type, payload in parse_attrs(msg[4:]):
                if attr_type != TASKSTATS_TYPE_AGGR_PID:
                    continue
                for inner_type, inner in parse_attrs(payload):
                    if inner_type == TASKSTATS_TYPE_STATS:
                        on_exit(inner)


def cg_usage():
    stat = dict(line.split() for line in read(CG_STAT).decode().splitlines())
    return int(stat["usage_usec"]), int(stat["user_usec"]), int(stat["system_usec"])


def dump(t0, t1, usage0, usage1, names):
    with lock:
        rows = []
        for (uid, key), (count, cpu, ut, st) in exited.items():
            rows.append({"user": names.get(uid, str(uid)), "key": key, "kind": "exited",
                         "count": count, "cpu_s": cpu / 1e9, "utime_s": ut / 1e6, "stime_s": st / 1e6})
        for (uid, key), cpu in alive.items():
            rows.append({"user": names.get(uid, str(uid)), "key": key, "kind": "alive", "cpu_s": cpu / 1e9})
        snapshot = dict(counters)
        exited.clear()
        alive.clear()
        for k in ("unattributed_exits", "unattributed_ns", "host_exits", "recv_errors"):
            counters[k] = 0
    out = {
        "vmid": VMID, "start": t0, "end": t1,
        "cgroup_cpu_s": (usage1[0] - usage0[0]) / 1e6,
        "cgroup_user_s": (usage1[1] - usage0[1]) / 1e6,
        "cgroup_system_s": (usage1[2] - usage0[2]) / 1e6,
        "counters": snapshot,
        "rows": sorted(rows, key=lambda r: -r["cpu_s"]),
    }
    name = time.strftime("%Y%m%dT%H%M%S", time.localtime(t0))
    tmp = os.path.join(OUT_DIR, f".{name}.json")
    with open(tmp, "w") as f:
        json.dump(out, f)
    os.rename(tmp, os.path.join(OUT_DIR, f"{name}.json"))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    names = uid_names()
    sock = open_taskstats()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    threads = [threading.Thread(target=scanner, daemon=True),
               threading.Thread(target=listener, args=(sock,), daemon=True)]
    for t in threads:
        t.start()
    end = time.time() + HOURS * 3600
    t0, usage0 = time.time(), cg_usage()
    while not stop.is_set() and time.time() < end:
        stop.wait(min(3600 - (time.time() - t0), end - time.time(), 60))
        if time.time() - t0 >= 3600 or stop.is_set() or time.time() >= end:
            t1, usage1 = time.time(), cg_usage()
            dump(t0, t1, usage0, usage1, names)
            t0, usage0 = t1, usage1
    stop.set()


if __name__ == "__main__":
    main()
