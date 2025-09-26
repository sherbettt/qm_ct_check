#!/bin/bash

echo "Сбор всех VM (QEMU) со всех узлов"
echo "-------------"
echo "VMID,Type,Name,Node,Status"
for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
  ssh $node "qm list" | tail -n +2 | awk -v node=$node '{print $1 ",qemu," $2 "," node "," $3}'
done

echo "=============================="

echo "Сбор всех CT (LXC) со всех узлов"
echo "-------------"
echo "VMID,Type,Name,Node,Status"
for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
  ssh $node "pct list" | tail -n +2 | awk -v node=$node '{print $1 ",lxc," $4 "," node "," $2}'
done

echo "=============================="
