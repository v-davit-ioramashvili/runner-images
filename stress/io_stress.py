#!/usr/bin/env python3
"""Sustained mixed disk load: small files with fsync, SQLite, mmap, retained bulk data, fresh binaries."""
import hashlib, json, multiprocessing as mp, mmap, os, random, shutil, sqlite3, subprocess, sys, time

ROOT, MINUTES, RETAIN_GIB, REPORT = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
END = time.time() + MINUTES * 60
BUF = os.urandom(1 << 22)


def note(name, stats, op, exc):
    key = f"{op}:{type(exc).__name__}:{getattr(exc, 'errno', '')}"
    stats[key] = stats.get(key, 0) + 1
    if stats[key] <= 5:
        print(f"[{time.strftime('%H:%M:%S')}] {name} {key} {exc}", flush=True)


def save(name, stats):
    tmp = f"{REPORT}.{name}.tmp"
    with open(tmp, "w") as f:
        json.dump(stats, f)
    os.replace(tmp, f"{REPORT}.{name}.json")


def small(i):
    name, stats, n = f"small{i}", {"ops": 0}, 0
    base = os.path.join(ROOT, name)
    os.makedirs(base, exist_ok=True)
    while time.time() < END:
        d = os.path.join(base, f"b{n}")
        n += 1
        try:
            os.makedirs(d)
            sums = {}
            for k in range(300):
                data = BUF[random.randrange(1 << 21):][:random.randrange(512, 1 << 16)]
                tmp = os.path.join(d, f".t{k}")
                fd = os.open(tmp, os.O_CREAT | os.O_WRONLY)
                os.write(fd, data)
                os.fsync(fd)
                os.close(fd)
                final = os.path.join(d, f"f{k}")
                os.rename(tmp, final)
                os.link(final, final + ".l")
                sums[final] = hashlib.sha1(data).hexdigest()
                stats["ops"] += 1
            for p, s in sums.items():
                with open(p, "rb") as f:
                    if hashlib.sha1(f.read()).hexdigest() != s:
                        stats["mismatch"] = stats.get("mismatch", 0) + 1
            if n % 2:
                shutil.rmtree(d, ignore_errors=True)
        except Exception as e:
            note(name, stats, "small", e)
            time.sleep(1)
        save(name, stats)


def db(i):
    name, stats, n = f"db{i}", {"ops": 0}, 0
    base = os.path.join(ROOT, name)
    os.makedirs(base, exist_ok=True)
    while time.time() < END:
        p = os.path.join(base, f"t{n}.db")
        n += 1
        try:
            c = sqlite3.connect(p)
            c.execute("PRAGMA journal_mode=WAL")
            c.execute("PRAGMA synchronous=FULL")
            c.execute("CREATE TABLE t(a INTEGER PRIMARY KEY, b BLOB)")
            for k in range(2000):
                c.execute("INSERT INTO t(b) VALUES (?)", (BUF[k:k + 2048],))
                if k % 20 == 0:
                    c.commit()
                stats["ops"] += 1
            c.commit()
            c.close()
        except Exception as e:
            note(name, stats, "sqlite", e)
            time.sleep(1)
        save(name, stats)


def mapped(i):
    name, stats = f"mmap{i}", {"ops": 0}
    base = os.path.join(ROOT, name)
    os.makedirs(base, exist_ok=True)
    size = 1 << 27
    p = os.path.join(base, "m.bin")
    while time.time() < END:
        try:
            with open(p, "wb") as f:
                f.truncate(size)
            with open(p, "r+b") as f:
                m = mmap.mmap(f.fileno(), size)
                for off in range(0, size, 1 << 14):
                    m[off:off + 64] = BUF[off % (1 << 21):][:64]
                m.flush()
                m.close()
            stats["ops"] += 1
            os.remove(p)
        except Exception as e:
            note(name, stats, "mmap", e)
            time.sleep(1)
        save(name, stats)


def bulk():
    name, stats, written = "bulk", {"ops": 0}, 0
    base = os.path.join(ROOT, name)
    os.makedirs(base, exist_ok=True)
    chunk = 1 << 28
    files = []
    while time.time() < END:
        try:
            if written < RETAIN_GIB << 30:
                p = os.path.join(base, f"r{len(files)}.bin")
                with open(p, "wb") as f:
                    for off in range(0, chunk, len(BUF)):
                        f.write(BUF)
                    f.flush()
                    os.fsync(f.fileno())
                files.append(p)
                written += chunk
                stats["retained_gib"] = written >> 30
            else:
                p = random.choice(files)
                with open(p, "r+b") as f:
                    f.seek(random.randrange(0, chunk - len(BUF)))
                    f.write(BUF)
                    f.flush()
                    os.fsync(f.fileno())
                time.sleep(0.2)
            stats["ops"] += 1
        except Exception as e:
            note(name, stats, "bulk", e)
            time.sleep(1)
        save(name, stats)


def fresh_exec(i):
    name, stats, n = f"exec{i}", {"ops": 0}, 0
    base = os.path.join(ROOT, name)
    os.makedirs(base, exist_ok=True)
    src = os.path.join(base, "h.c")
    with open(src, "w") as f:
        f.write("int main(void){return 0;}\n")
    while time.time() < END:
        out = os.path.join(base, f"h{n % 50}")
        n += 1
        try:
            if os.path.exists(out):
                os.remove(out)
            subprocess.run(["cc", "-O0", "-o", out, src], check=True, capture_output=True)
            r = subprocess.run([out], capture_output=True)
            if r.returncode:
                stats["exec_fail"] = stats.get("exec_fail", 0) + 1
                print(f"[{time.strftime('%H:%M:%S')}] {name} rc={r.returncode} {r.stderr[:200]}", flush=True)
            stats["ops"] += 1
        except Exception as e:
            note(name, stats, "exec", e)
            time.sleep(1)
        save(name, stats)


if __name__ == "__main__":
    os.makedirs(ROOT, exist_ok=True)
    procs = [mp.Process(target=small, args=(i,)) for i in range(4)]
    procs += [mp.Process(target=db, args=(i,)) for i in range(2)]
    procs += [mp.Process(target=mapped, args=(i,)) for i in range(2)]
    procs += [mp.Process(target=fresh_exec, args=(i,)) for i in range(2)]
    procs += [mp.Process(target=bulk)]
    for p in procs:
        p.start()
    for p in procs:
        p.join()
    print("done", flush=True)
