#!/usr/bin/env python3
"""Host-only experiment: Keychain and advisory file locks across separate processes."""
import pathlib, subprocess, tempfile, time, uuid

source = pathlib.Path(__file__).with_name("pricebook-lease-process-probe.swift")
service = "com.thorbis.field.test-only-process-lease." + str(uuid.uuid4())
with tempfile.TemporaryDirectory(prefix="thorbis-lease-process-") as root:
    binary = pathlib.Path(root) / "probe"
    subprocess.run(["xcrun", "swiftc", str(source), "-o", str(binary)], check=True)
    args = lambda mode: [str(binary), mode, service, root]
    owner = subprocess.Popen(args("owner"), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 15
        while not (pathlib.Path(root) / "ready").exists():
            if owner.poll() is not None:
                raise RuntimeError(f"owner failed: {owner.returncode}, {owner.stderr.read().decode()}")
            if time.monotonic() > deadline:
                raise TimeoutError("owner did not establish its marker")
            time.sleep(.05)
        blocked = subprocess.run(args("probe"), capture_output=True)
        assert blocked.returncode == 75, f"contending process was not excluded: exit {blocked.returncode}, {blocked.stderr.decode()}"
        owner.kill()
        owner.wait(timeout=5)
        recovered = subprocess.run(args("probe"), capture_output=True)
        assert recovered.returncode == 0, f"crash recovery did not observe dirty marker: exit {recovered.returncode}, {recovered.stderr.decode()}"
        print("PASS: second process excluded; after owner termination it acquired the lock and observed dirty Keychain state")
    finally:
        if owner.poll() is None:
            owner.kill(); owner.wait(timeout=5)
        subprocess.run(args("cleanup"), check=True)
