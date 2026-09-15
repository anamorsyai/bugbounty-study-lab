#!/bin/bash
# diagnose-vmware.sh -- read-only diagnostic for the Alpine VMware lab.
# Run from Git Bash. Prints everything needed to tell why vmrun start fails silently.
# Usage: bash <skill>/scripts/diagnose-vmware.sh

VMX="/c/Users/<your-user>/Documents/Virtual Machines/Alpine/Alpine.vmx"
VMRUN="/c/Program Files/VMware/VMware Workstation/vmrun.exe"

echo "=============================================="
echo "  VMware Alpine Lab - Diagnostics"
echo "=============================================="

echo
echo "[1] Hypervisor / VMware processes"
tasklist 2>/dev/null | grep -iE "vmware|vmx|vmnat" || echo "    (none found)"

echo
echo "[2] Virtualization platform (Windows feature)"
systeminfo 2>/dev/null | grep -iE "hyper-v|virtualization|hypervisor" || echo "    (unavailable)"

echo
echo "[3] vmrun list"
"$VMRUN" list 2>&1 || echo "    vmrun failed"

echo
echo "[4] VMX file"
if [ -f "$VMX" ]; then
  echo "    exists, size=$(stat -c%s "$VMX")"
  echo "    mtime=$(stat -c%y "$VMX")"
  echo "    --- key settings ---"
  grep -iE "^(displayName|guestOS|numvcpus|memsize|ethernet0|scsi0|nvme0|floppy|serial|usb)" "$VMX" | head -30
  echo "    --- encoding check ---"
  head -c 3 "$VMX" | xxd | head -1
else
  echo "    MISSING: $VMX"
fi

echo
echo "[5] Log freshness (did a start attempt even reach the hypervisor?)"
for f in vmware.log vmware-0.log vmware-1.log vmware-2.log; do
  p="$(dirname "$VMX")/$f"
  [ -f "$p" ] && echo "    $f  mtime=$(stat -c%y "$p")"
done

echo
echo "[6] Tail of current vmware.log"
tail -n 25 "$(dirname "$VMX")/vmware.log" 2>&1 || echo "    (no log)"

echo
echo "=============================================="
echo "  Done. If [5] shows a stale log after a start"
echo "  attempt, the failure is BEFORE the hypervisor"
echo "  (VMX parse / permissions / platform)."
echo "=============================================="
