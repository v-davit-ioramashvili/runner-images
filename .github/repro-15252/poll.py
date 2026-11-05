"""Host-side poller for #15252.

Every 0.25 s: record each new or changed process whose command line mentions
xpcproxy_sim / TextInput / kbd / InputUI, so the kbd PID's change from
xpcproxy_sim (spawn) to the kbd binary (running) is timed like the reporter's
"proxy -> running" interval. Every 1 s: load average and simdiskimaged CPU.
"""
import datetime
import os
import subprocess
import sys
import time

out = open(sys.argv[1], "a", buffering=1)
seen = {}
last_load = 0.0


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds")


while True:
    try:
        ps = subprocess.run(["ps", "-axo", "pid=,ppid=,pcpu=,command="],
                            capture_output=True, text=True, timeout=5).stdout
    except Exception:
        time.sleep(0.25)
        continue
    t = now()
    simdisk = []
    for line in ps.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        pid, ppid, cpu, cmd = parts
        if any(k in cmd for k in ("xpcproxy_sim", "TextInput", "/kbd", "InputUI")):
            if seen.get(pid) != cmd:
                out.write(f"{t} PROC pid={pid} ppid={ppid} cmd={cmd[:240]}\n")
                seen[pid] = cmd
        if "simdiskimaged" in cmd:
            simdisk.append(cpu)
    if time.time() - last_load >= 1:
        l1, _, _ = os.getloadavg()
        out.write(f"{t} LOAD load1={l1:.2f} simdiskimaged_cpu={','.join(simdisk) or 'none'}\n")
        last_load = time.time()
    time.sleep(0.25)
