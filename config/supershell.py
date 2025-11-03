#!/usr/bin/env python3
import asyncio, shlex, sys, os

VMs = {
    "vm1": ("localhost", 2221),
    "vm2": ("localhost", 2222),
    "vm3": ("localhost", 2223),
}

SSH_KEY = "vms/sshkey/id_ed25519"
USER = "u"

ctx_cwd = "/home/u"
ctx_env = {}

COLOR_RESET = "\033[0m"
VM_COLORS = {
    "vm1": "\033[1;34m",  # bright blue
    "vm2": "\033[1;33m",  # bright yellow
    "vm3": "\033[1;35m",  # bright magenta
}
ERR_COLOR = "\033[1;31m"  # bright red
USE_COLOR = sys.stdout.isatty()

def build_remote_cmd(cmd: str):
    exports = " ".join([f"export {k}={shlex.quote(v)};" for k, v in ctx_env.items()])
    prefix = f"cd {shlex.quote(ctx_cwd)}; {exports}" if exports else f"cd {shlex.quote(ctx_cwd)};"
    wrapped = f"bash -lc {shlex.quote(prefix + ' ' + cmd)}"
    return wrapped

async def run_on_vm(vm, host, port, cmd):
    remote = build_remote_cmd(cmd)
    proc = await asyncio.create_subprocess_exec(
        "ssh",
        "-i", SSH_KEY,
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        f"{USER}@{host}", "-p", str(port),
        remote,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    async def read_stream(stream, is_err=False):
        if USE_COLOR:
            vm_color = VM_COLORS.get(vm, "")
            err_color = ERR_COLOR if is_err else ""
            prefix = f"{vm_color}[{vm}]{COLOR_RESET}"
            if is_err:
                prefix += f"{err_color}[ERR]{COLOR_RESET}"
            prefix += " "
        else:
            prefix = f"[{vm}]{'[ERR]' if is_err else ''} "
        while True:
            line = await stream.readline()
            if not line:
                break
            sys.stdout.write(prefix + line.decode(errors="replace"))
            sys.stdout.flush()

    await asyncio.gather(read_stream(proc.stdout), read_stream(proc.stderr, True))
    rc = await proc.wait()
    return rc

async def parse_builtin(line):
    global ctx_cwd, ctx_env
    parts = line.strip().split()
    if not parts:
        return True
    cmd = parts[0]

    if cmd in ("exit", "quit", ":q"):
        sys.exit(0)

    if cmd == "cd" and len(parts) > 1:
        path = parts[1]
        # Expand tilde and environment variables
        path = os.path.expandvars(os.path.expanduser(path))
        if not os.path.isabs(path):
            ctx_cwd = os.path.normpath(os.path.join(ctx_cwd, path))
        else:
            ctx_cwd = path
        print(f"[supershell] cwd → {ctx_cwd}")
        return True

    if cmd == "export" and len(parts) > 1 and "=" in parts[1]:
        key, val = parts[1].split("=", 1)
        ctx_env[key] = val
        print(f"[supershell] export {key}={val}")
        return True

    if line.strip() == ":poweroff":
        print("[supershell] powering off all VMs...")
        tasks = [run_on_vm(vm, host, port, "sudo poweroff") for vm, (host, port) in VMs.items()]
        await asyncio.gather(*tasks)
        print("[supershell] all VMs are shutting down.")
        return True
    
    if line.startswith(":pull"):
        import subprocess, os
        parts = line.split()
        if len(parts) < 3:
            print("[supershell] Usage: :pull <remote_path> <local_path>")
            return True
        remote_path = parts[1]
        local_path = parts[2]
        os.makedirs(local_path, exist_ok=True)
        vm_ports = {"vm1": 2221, "vm2": 2222, "vm3": 2223}
        key_path = "vms/sshkey/id_ed25519"

        for vm, port in vm_ports.items():
            vm_dest = os.path.join(local_path, vm)
            os.makedirs(vm_dest, exist_ok=True)
            print(f"[supershell] Pulling from {vm}:{remote_path} → {vm_dest}/")
            cmd = [
                "scp",
                "-i", key_path,
                "-P", str(port),
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-r", f"u@localhost:{remote_path.rstrip('/')}/.",
                vm_dest,
            ]
            subprocess.run(cmd)
        return True

    return False

async def repl():
    print("=== SuperShell ===")
    print("Type commands to run on vm1-vm3.")
    print("Built-ins: cd, export, :poweroff, exit|quit|:q")
    while True:
        try:
            line = input("supersh> ").strip()
        except EOFError:
            break
        if not line:
            continue
        if await parse_builtin(line):
            continue
        tasks = [run_on_vm(vm, host, port, line) for vm, (host, port) in VMs.items()]
        results = await asyncio.gather(*tasks, return_exceptions=False)
        print(f"[supershell] exit codes: {dict(zip(VMs.keys(), results))}")

if __name__ == "__main__":
    asyncio.run(repl())
