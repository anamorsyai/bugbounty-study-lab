---
name: vmware-alpine
description: Control the local VMware Alpine Linux VM — start/stop/reboot it headless via vmrun, wait for SSH, open an interactive session, and mirror host ports into (or out of) the guest. Use whenever a task needs a Linux box, an isolated lab target, or a place to run tooling without touching the host — especially any cybersecurity research, exploit lab, or reproduction where an ephemeral disposable Linux environment is the right move. Triggers on "spin up a VM", "use the lab", "run this in Linux", "set up a target", "start alpine", "give me a Linux box".
agent_created: true
---

# VMware Alpine Lab Control

The operator keeps an Alpine Linux VM on VMware Workstation. This skill is the standard way
to get a Linux environment up and available. **Prefer it over wrestling with the host
for anything Linux-native.**

**Status: WORKING (verified 2026-09-14).** Start → VM registers → SSH answers in ~15–30s.
Current guest: Alpine 3.24.1, kernel 6.18.44-0-virt, IP `192.168.241.128`.

## Fixed Environment Facts

| Thing | Value |
|---|---|
| `vmrun` | `C:\Program Files\VMware\VMware Workstation\vmrun.exe` |
| VMX path | `C:\Users\<your-user>\Documents\Virtual Machines\Alpine\Alpine.vmx` |
| SSH alias | `alpine` (defined in `~/.ssh/config`) |
| Host | `192.168.241.128` (DHCP — can change, see below) |
| User | `root` |
| Key | `~/.ssh/alpine_key` |
| Guest | Alpine Linux 3.24.1, 2 vCPU, 8192 MB RAM, NAT (e1000) |
| Boot-to-SSH | ~15–30s observed; budget 60s |

If a value above has changed, update BOTH this file and the helper script — never only one.

## Standing Ports

The original launcher mirrored these. They are the house defaults — reuse them unless a
task needs something else:

| Port | Direction | Purpose |
|---|---|---|
| `9876` | `-R` guest→host | callback / reverse-shell listener |
| `3333` | `-R` guest→host | alternate callback channel |
| `8089` | `-L` host→guest | host reaches services running in the guest |

## Primary Interface: `scripts/alpine.ps1`

Everything goes through one wrapper. Run it from PowerShell.

```powershell
# Bring the lab up and drop into an interactive root shell (default)
powershell -ExecutionPolicy Bypass -File <skill>/scripts/alpine.ps1

# Start headless, don't attach a shell — for scripted use
powershell -ExecutionPolicy Bypass -File <skill>/scripts/alpine.ps1 -Action start

# Just stop it
powershell -ExecutionPolicy Bypass -File <skill>/scripts/alpine.ps1 -Action stop

# Run one command inside the guest and return (no interactive session)
powershell -ExecutionPolicy Bypass -File <skill>/scripts/alpine.ps1 -Action ssh -Command "uname -a"

# Copy a file in / out
powershell -ExecutionPolicy Bypass -File <skill>/scripts/alpine.ps1 -Action put -Local ./tool.py -Remote /root/tool.py
powershell -ExecutionPolicy Bypass -File <skill>/scripts/alpine.ps1 -Action get -Remote /root/loot.txt -Local ./loot.txt

# Snapshot before something destructive, revert after
powershell -ExecutionPolicy Bypass -File <skill>/scripts/alpine.ps1 -Action snapshot -Name clean
powershell -ExecutionPolicy Bypass -File <skill>/scripts/alpine.ps1 -Action revert -Name clean
```

## Workflow — The Standard Sequence

1. **Check state first.** `vmrun list` shows running VMs. Don't start a VM that's already up.
2. **Start** with `-Action start` when you need the machine but not a human at the console.
   Output is silent by design — verify success with a follow-up `-Action ssh -Command "true"`.
3. **Verify SSH is actually reachable** before assuming the box is ready. Boot is ~45s but can vary.
   Poll-once is better than blind-sleeping.
4. **Do the work** — transfer tooling in with `put`, run it, pull artifacts out with `get`.
5. **Snapshot before anything destructive.** The whole point of the lab is that it's disposable.
   If a task is going to wreck state, snapshot first and say so.
6. **Stop it when done** unless you say to leave it up. `-Action stop` is a hard stop
   (instant), which is what we want for a disposable lab.

## Failure Modes and How to Read Them

### ⚠️ THE BIG ONE: `vmrun start` returns exit 0 but nothing happens

Symptoms, together:
- `vmrun start <vmx> nogui` → **exit code 0** (looks like success)
- `vmrun list` → `Total running VMs: 0`
- `vmware.log` gets **zero new lines** (check its mtime)

Exit 0 + stale log = the command was accepted but the **VMX never parsed**, so the
hypervisor never even attempted a boot. Run `scripts/diagnose-vmware.sh`; section [5]
settles it instantly (stale log = parse failure, fresh log = the problem is later).

**Root cause found 2026-09-14: the VMX had been left in checkpoint/suspend state.**

The broken VMX contained these keys, which pin the VM to a saved suspend state:

```
checkpoint.vmState = "Alpine-9ccbbfc0.vmss"
vm.lastPowerRequestTimestamp = "1789124509458000"
cleanShutdown = "FALSE"
softPowerOff = "FALSE"
```

Plus a stray `vm.createDate` and a leading `.encoding = "UTF-8"` that shouldn't lead the file.

**The fix that worked** (kept clean VMX in `Alpine.vmx`, broken one in `Alpine.vmx.bak-*`):

1. Back up the VMX: `cp Alpine.vmx Alpine.vmx.bak-$(date +%Y%m%d-%H%M%S)`
2. Write a clean VMX with **no** checkpoint keys — drop `checkpoint.vmState`,
   `vm.lastPowerRequestTimestamp`, `cleanShutdown`, `softPowerOff`, `vm.createDate`.
   Keep everything else (uuid, MAC, PCI slots, disk, ISO, NAT).
3. Add `sata0:1.startConnected = "TRUE"` so the CD is attached if a boot-from-ISO is needed.
4. `vmrun start <vmx> nogui` → VM registers, SSH up in ~15–30s.

There's a template of the known-good VMX below. **Never delete `Alpine.vmdk`** (25 GB —
that's the actual filesystem).

### Other failure modes

- **`vmrun` non-zero on start** → VMX path wrong, or VMware not licensed/installed.
- **SSH times out but the VM IS running** → sshd not started, or the guest IP moved.
  The IP is DHCP; a long-shut-down VM can get a different lease. Re-derive it with:
  `vmrun getGuestIPAddress "<vmx>" -wait`. Keep `~/.ssh/config` + this file in sync.
- **SSH refuses the key** → `StrictHostKeyChecking=no` only silences the *host-key* prompt.
  A key rejection means `alpine_key` perms are wrong or the pubkey isn't in the guest's
  `/root/.ssh/authorized_keys`.
- **Port already in use (`ExitOnForwardFailure`)** → a stale SSH session or local listener
  holds the port. `netstat -ano | findstr <port>`, kill it, or pass alternate ports.
- **No stale `.lck` dirs** in the VM folder was confirmed — don't waste time hunting for them.

### Known-good VMX template

Kept at `scripts/alpine-known-good.vmx`. If the VMX breaks again, copy that over
`Alpine.vmx` (after backing up the broken one) and start. Adjust paths if the ISO moves.

## Running This Skill as an Agent (not a human at a console)

Hard-won gotchas — read these before improvising:

- **`vmrun` stdout is NOT reliably captured by PowerShell's `&` operator** in the agent
  harness. The call returns a bare "exit code 0" and no stdout. **Fix: redirect to a temp
  file and read it back.** That's what `Get-VmRunning` in `alpine.ps1` does. Do the same
  for any new vmrun call you add.
- **Quick manual checks are easiest through Git Bash**: 
  `"C:/Program Files/VMware/VMware Workstation/vmrun.exe" list` prints clean output there.
- Invoking PowerShell *from* Bash is blocked by policy — use the PowerShell tool for script
  runs, Bash for direct vmrun/ssh checks.
- Use `-Action start`, never the interactive `shell` action, when acting autonomously.
  Interactive `shell` hands the console to a TTY nobody is typing into.
- Guest commands: non-interactive SSH with
  `-o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no -i <key>`, then check
  the exit code. Don't blind-sleep 45s — poll in a bounded loop and report what you saw.
- Prefer the `ssh alpine` alias in interactive use; the raw `-i key root@ip` form in scripts.

## Notes for the Assistant

- This is an **isolated lab**. Work here freely and creatively; it's your own machine
  and his own hypervisor, and nothing touches production or third parties.
- The guest is Alpine — `apk add <pkg>`, not `apt`. BusyBox userland: use `sh`, expect
  limited coreutils, and don't assume GNU flags (`netstat -tln` works; `ss` may need install).
- The `ssh alpine` alias (defined in `~/.ssh/config` on the host) is the clean way to run
  guest commands from the agent: `ssh alpine "command here"`. It works through Git Bash.
- OpenSSH is already running on the guest (`0.0.0.0:22`).

### Guest environment map (as of 2026-09-14)

This is NOT a vanilla Alpine — it's a purpose-built bug bounty hunting rig. Know what's
here before installing duplicates.

**Running services:**

| Port | Process | What it is |
|---|---|---|
| `22` | `sshd` | SSH — our access point |
| `8080` | `code-server` (4.133.0) | VS Code in browser, `bind-addr: 0.0.0.0:8080`, password auth |
| `9086` | `anthropic-shim` (localhost only) | Claude→OpenAI translation proxy with multi-provider failover chain |
| `9087` | `rig-dashboard` (Node.js) | Rig control dashboard |

**Hunting tools in `/usr/local/bin/`:**

| Category | Tools |
|---|---|
| Recon / subdomains | `subfinder`, `assetfinder`, `amass`, `massdns`, `puredns`, `alterx`, `dnsx`, `mapcidr` |
| Port scan | `naabu`, `nmap` |
| HTTP probing | `httpx`, `whatweb`, `ffuf`, `gobuster`, `feroxbuster` |
| Crawling / URLs | `gau`, `waybackurls`, `katana`, `gospider`, `hakrawler`, `getJS`, `unfurl`, `qsreplace`, `anew`, `gf`, `kxss` |
| Vuln scanning | `nuclei` (v3.11.1), `nikto` (2.6.0), `testssl.sh` |
| Exploitation | `jwt_tool`, `interactsh-client`, `subzy` (subdomain takeover), `dalfox` (XSS) |
| Secrets | `trufflehog` |
| Impersonation | `curl-impersonate` (Chrome 99–150, Edge, Firefox 133–135 TLS/JA3 profiles) |
| AI / dev | `claude` (Claude Code), `opencode`, `cline` |

**Resource directories:**

| Path | Contents |
|---|---|
| `/opt/PayloadsAllTheThings` | Payload repository (70 subdirs) |
| `/opt/SecLists` | Daniel Miessler's SecLists (Discovery, Fuzzing, Passwords, Usernames, Payloads) |
| `/opt/fuzzdb` | FuzzDB attack patterns |
| `/opt/jwt_tool` | JWT analysis tool |
| `/opt/testssl.sh` | TLS/SSL testing |
| `/opt/whatweb` | Tech fingerprinting |
| `/opt/wordlists` | Assetnote wordlists |
| `/root/nuclei-templates` | Nuclei templates (31 top-level dirs: cves, dast, cloud, etc.) |
| `/root/hunting-rig` | The main rig — see below |
| `/root/go/bin/subzy` | Go binary (also symlinked in /usr/local/bin) |

**The hunting rig (`/root/hunting-rig/`):**

| Subdir | Contents |
|---|---|
| `payloads/` | 23 bug classes: `sqli`, `xss`, `ssrf`, `ssti`, `cmdi`, `cors`, `idor`, `jwt`, `oauth`, `graphql`, `nosql`, `race`, `rate-limit`, `smuggling`, `path-traversal`, `deserialization`, `xxe`, `upload`, `cache-poison`, `bizlogic`, `auth`, `api` |
| `agents/` | 8 agent dirs: orchestration, verify-report, recon, intel, secrets-explore, web-attack, api-cloud, support |
| `instructions/` | 16 methodology docs (HUNT-METHODOLOGY, SESSION-STARTUP, AUTHORIZED-ENGAGEMENT-PROTOCOL, etc.) |
| `wordlists/` | 21 wordlists including `rockyou.txt`, `subdomains-top5000.txt`, raft large/small dirs+files |
| `tools/` | (root-level) tool index |

**Recon pipeline (`/root/tools/recon/`):**

7 numbered scripts forming a full pipeline:
`01-passive` → `02-active` → `03-content` → `04-crawl` → `05-secrets` → `06-fingerprint` → `07-report`
plus `lib.sh` (shared functions) and `recon.sh` (wrapper).

**The rig-portable (`/root/workspaces/rig-portable/`):**

A portable Claude Code hunting environment — 171 skills, 27 commands, 11 agents.
`anthropic-shim.mjs` is a Go-compiled Anthropic→OpenAI translation proxy with a
multi-provider failover chain (DeepSeek-V4-Flash primary → zen → Kimi → bynara).
Installable on new devices via `install-new-device.sh`.

**Methodology (`HUNT-METHODOLOGY.md`):**

9-phase hunt: Intake & Scope Lock → Full Recon → Lateral Hypothesis Generation →
Full Technical Testing (The Hunt) → Deep Business Logic → Technical Verification →
Chain Analysis → Adversarial Verification → Report Writing.
Recursive loop with decision gates. Autonomous hunt mode: `hunt on <target>`.

- The VM has 8 GB RAM and a 45 GB disk (12 GB used, 32 GB free) — plenty for heavier tooling.
  **Snapshot before destructive work.**
