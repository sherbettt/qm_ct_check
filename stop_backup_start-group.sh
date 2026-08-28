#!/bin/bash

for VM in {210..213}; do
    echo "=== Reroll $VM ==="

    pct stop $VM
    BACKUP_TAR=$(ls /stg/1tb/dump/vzdump-lxc-${VM}-*.tar.zst 2>/dev/null)

if [ -n "$BACKUP_TAR" ]; then
    echo "Dump for $VM  has been found"
else
    echo "Dump for $VM hasn't been found"
fi

    pct restore $VM /stg/1tb/dump/vzdump-lxc-${VM}-*.tar.zst --storage ssd_1tb --force && pct start $VM
    pct status $VM
done
