#!/bin/bash

TARGET_IP="${1:-192.168.87.209}"

echo "Быстрый поиск IP: $TARGET_IP"
echo "============================="

# Проверяем доступность
ping -c 1 -W 1 "$TARGET_IP" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "✗ IP недоступен"
    exit 1
fi

echo "✓ IP доступен"

# Используем ip neigh вместо arp
NEIGH_INFO=$(ip neigh show | grep "$TARGET_IP")
if [ -n "$NEIGH_INFO" ]; then
    MAC=$(echo "$NEIGH_INFO" | awk '{print $5}')
    echo "MAC адрес: $MAC"

    # Ищем на всех узлах кластера
    for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
        echo "Узел: $node"

        # Проверяем CT
        ssh $node "pct list" 2>/dev/null | awk 'NR>1 {print $1}' | while read ctid; do
            IP=$(ssh $node "pct exec $ctid hostname -I 2>/dev/null" | xargs echo)
            if echo " $IP " | grep -q " $TARGET_IP "; then
                ct_name=$(ssh $node "pct config $ctid" 2>/dev/null | grep '^hostname:' | awk '{print $2}')
                echo "✓ НАЙДЕНО: CT $ctid ($ct_name)"
                exit 0
            fi
        done

        # Проверяем VM
        ssh $node "qm list" 2>/dev/null | awk 'NR>1 {print $1}' | while read vmid; do
            IP=$(ssh $node "qm guest cmd $vmid network-get-interfaces 2>/dev/null" | grep -oP '"ip-address":"\K[^"]+' | head -1)
            if [ "$IP" = "$TARGET_IP" ]; then
                vm_name=$(ssh $node "qm config $vmid" 2>/dev/null | grep '^name:' | awk '{print $2}')
                echo "✓ НАЙДЕНО: VM $vmid ($vm_name)"
                exit 0
            fi
        done
    done
else
    echo "⚠ IP не в таблице соседей - возможно, это не L2 сосед"
fi

echo "? IP не найден в кластере Proxmox"

