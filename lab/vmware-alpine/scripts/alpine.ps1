<#
.SYNOPSIS
    Control the local VMware Alpine lab VM.

.DESCRIPTION
    Starts/stops the Alpine VM headless, opens an interactive SSH session, runs one-off
    remote commands, copies files in/out, and manages snapshots. Ports 9876/3333 are
    mirrored guest->host, 8089 host->guest, matching the original house config.

.PARAMETER Action
    start    - start the VM headless (no shell attached). Default is 'shell'.
    stop     - hard-stop the VM.
    reboot   - stop then start.
    status   - report whether the VM is running, and whether SSH answers.
    shell    - start if needed, then attach an interactive root shell (DEFAULT).
    ssh      - start if needed, then run -Command in the guest and return.
    put      - copy a local file into the guest  (-Local, -Remote).
    get      - copy a file out of the guest      (-Remote, -Local).
    snapshot - take a named snapshot (-Name).
    revert   - revert to a named snapshot (-Name).

.EXAMPLE
    .\alpine.ps1
    .\alpine.ps1 -Action start
    .\alpine.ps1 -Action ssh -Command "uname -a"
    .\alpine.ps1 -Action put -Local .\tool.py -Remote /root/tool.py
    .\alpine.ps1 -Action snapshot -Name clean
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('start','stop','reboot','status','shell','ssh','put','get','snapshot','revert')]
    [string]$Action = 'shell',

    [string]$Command,
    [string]$Local,
    [string]$Remote,
    [string]$Name,

    [switch]$NoWait,
    [int]$BootWait = 45,

    [int]$TunnelPort1 = 9876,
    [int]$TunnelPort2 = 3333,
    [int]$TunnelPort3 = 8089
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# CONFIGURATION  -- keep in sync with SKILL.md
# --------------------------------------------------------------------------
$vmrun     = "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
$TargetVMX = "C:\Users\<your-user>\Documents\Virtual Machines\Alpine\Alpine.vmx"
$SSHUser   = "root"
$SSHHost   = "192.168.241.128"
$SSHKey    = "$env:USERPROFILE\.ssh\alpine_key"

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
function Write-Step { param($n, $msg) Write-Host ""; Write-Host "  [$n] $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "        $msg" -ForegroundColor Green }
function Write-Warn2{ param($msg) Write-Host "        $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "        $msg" -ForegroundColor Red }

function Assert-Config {
    if (-not (Test-Path $vmrun))     { throw "vmrun not found at: $vmrun" }
    if (-not (Test-Path $TargetVMX)) { throw "VMX not found at: $TargetVMX" }
}

function Get-VmRunning {
    # IMPORTANT: vmrun's stdout is NOT reliably captured by PowerShell's &
    # operator in every host (the agent harness swallows it, returning a bare
    # "exit code 0"). Redirect to a temp file and read it back -- that always works.
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        & $vmrun list > $tmp 2>&1
        $list = Get-Content $tmp -ErrorAction SilentlyContinue
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    return [bool]($list | Where-Object { $_ -like "*Alpine*" })
}

function Test-SshAlive {
    # One-shot probe. Returns $true if the guest answers SSH.
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no `
                 -i $SSHKey "$SSHUser@$SSHHost" "true" 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Wait-ForSsh {
    param([int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-SshAlive) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Start-Vm {
    Assert-Config
    if (Get-VmRunning) { Write-Ok "Alpine already running." } else {
        Write-Host "        Starting Alpine (nogui)..." -ForegroundColor DarkGray
        & $vmrun start "$TargetVMX" nogui 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "vmrun start failed (exit $LASTEXITCODE)." }
        Write-Ok "VM start issued."
    }
    if ($NoWait) { return }

    # Two-stage wait: first for the VM to register with the hypervisor, then for SSH.
    Write-Host "        Waiting up to ${BootWait}s for the VM and SSH..." -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds($BootWait)
    $seen = $false
    while ((Get-Date) -lt $deadline) {
        if (Get-VmRunning) { $seen = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $seen) {
        Write-Warn2 "VM did not register as running within ${BootWait}s."
        Write-Warn2 "If vmware.log is also stale, the VMX failed to parse -- see SKILL.md."
        return
    }
    if (Test-SshAlive) { Write-Ok "VM running and SSH is up." }
    else {
        Write-Warn2 "VM is running but SSH is not answering yet."
        Write-Warn2 "It may still be booting, or the guest IP has changed (it is DHCP)."
    }
}

function Stop-Vm {
    Assert-Config
    if (-not (Get-VmRunning)) { Write-Ok "Alpine not running."; return }
    & $vmrun stop "$TargetVMX" hard 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    Write-Ok "Stopped."
}

function Invoke-Remote {
    param([string]$Cmd)
    $out = & ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 `
                 -i $SSHKey "$SSHUser@$SSHHost" $Cmd 2>&1
    $code = $LASTEXITCODE
    if ($out) { $out | ForEach-Object { Write-Host $_ } }
    if ($code -ne 0) { Write-Err "Remote command exited $code" }
    return $code
}

# --------------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------------
switch ($Action) {

    'start' {
        Start-Vm
    }

    'stop' {
        Stop-Vm
    }

    'reboot' {
        Stop-Vm
        Start-Sleep -Seconds 2
        Start-Vm
    }

    'status' {
        Write-Step '1/2' 'Checking VM state...'
        if (Get-VmRunning) { Write-Ok "VM is RUNNING." } else { Write-Warn2 "VM is stopped." }
        Write-Step '2/2' 'Probing SSH...'
        if (Test-SshAlive) { Write-Ok "SSH answers on ${SSHHost}." } else { Write-Warn2 "SSH not answering." }
    }

    'shell' {
        Start-Vm
        Write-Host ""
        Write-Host "        Attaching interactive shell. Ports: -R ${TunnelPort1}, -R ${TunnelPort2}, -L ${TunnelPort3}" -ForegroundColor DarkGray
        ssh `
            -R "${TunnelPort1}:127.0.0.1:${TunnelPort1}" `
            -R "${TunnelPort2}:127.0.0.1:${TunnelPort2}" `
            -L "${TunnelPort3}:127.0.0.1:${TunnelPort3}" `
            -o "ServerAliveInterval=15" `
            -o "ServerAliveCountMax=99999" `
            -o "TCPKeepAlive=yes" `
            -o "StrictHostKeyChecking=no" `
            -o "ExitOnForwardFailure=yes" `
            -i $SSHKey `
            -t "${SSHUser}@${SSHHost}" "clear; exec /bin/sh -l"
        Write-Host ""
        Write-Host "  SSH session ended." -ForegroundColor DarkYellow
    }

    'ssh' {
        if (-not $Command) { throw "-Action ssh requires -Command" }
        Start-Vm
        exit (Invoke-Remote -Cmd $Command)
    }

    'put' {
        if (-not $Local -or -not $Remote) { throw "-Action put requires -Local and -Remote" }
        Start-Vm
        & $vmrun -gu $SSHUser -gp "" copyFileFromHostToGuest "$TargetVMX" $Local $Remote 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # Fallback: scp
            & scp -o StrictHostKeyChecking=no -i $SSHKey $Local "${SSHUser}@${SSHHost}:${Remote}"
        }
        Write-Ok "Copied $Local -> $Remote"
    }

    'get' {
        if (-not $Remote -or -not $Local) { throw "-Action get requires -Remote and -Local" }
        Start-Vm
        & $vmrun -gu $SSHUser -gp "" copyFileFromGuestToHost "$TargetVMX" $Remote $Local 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & scp -o StrictHostKeyChecking=no -i $SSHKey "${SSHUser}@${SSHHost}:${Remote}" $Local
        }
        Write-Ok "Copied $Remote -> $Local"
    }

    'snapshot' {
        if (-not $Name) { throw "-Action snapshot requires -Name" }
        Start-Vm
        & $vmrun snapshot "$TargetVMX" $Name 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "snapshot failed" }
        Write-Ok "Snapshot '$Name' taken."
    }

    'revert' {
        if (-not $Name) { throw "-Action revert requires -Name" }
        Assert-Config
        & $vmrun revertToSnapshot "$TargetVMX" $Name 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "revert failed" }
        Write-Ok "Reverted to '$Name'."
    }
}
