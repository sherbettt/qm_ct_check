#!/bin/bash

DUMP_DIR="/stg/1tb/dump"
STORAGE="ssd_1tb"

if [ ! -d "$DUMP_DIR" ]; then
    echo "Directory $DUMP_DIR not found, exiting"
    exit 1
fi

for VM in {311..314}; do
    echo "=== Make backup for $VM ==="
    vzdump $VM --mode suspend --compress zstd  --storage "$STORAGE" --notes-template '{{vmid}}-{{guestname}}--autoBackup'
    pct status $VM
    echo " "
done

ls -alFS --si /stg/1tb/dump/vzdump-lxc-$VM-*
