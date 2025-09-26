#!/bin/bash

TARGET_IP="${1:-192.168.87.209}"

find_container_by_ip() {
    echo "Поиск контейнера/VM с IP: $TARGET_IP"
    echo "======================================"

    local result_file=$(mktemp)

    for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
        echo "Проверка узла: $node"

        # Поиск в CT
        ssh $node "pct list" 2>/dev/null | awk 'NR>1 {print $1}' | while read ctid; do
            [ -z "$ctid" ] && continue

            # Быстрая проверка через hostname -I
            IP=$(ssh $node "pct exec $ctid hostname -I 2>/dev/null" | xargs echo)
            if echo " $IP " | grep -q " $TARGET_IP "; then
                ct_name=$(ssh $node "pct config $ctid" 2>/dev/null | grep '^hostname:' | awk '{print $2}')
                echo "✓ НАЙДЕНО: CT $ctid ($ct_name) на узле $node" > "$result_file"
                return 0
            fi
        done

        # Поиск в VM
        ssh $node "qm list" 2>/dev/null | awk 'NR>1 {print $1}' | while read vmid; do
            [ -z "$vmid" ] && continue

            IP=$(ssh $node "qm guest cmd $vmid network-get-interfaces 2>/dev/null" | grep -oP '"ip-address":"\K[^"]+' | head -1)
            if [ "$IP" = "$TARGET_IP" ]; then
                vm_name=$(ssh $node "qm config $vmid" 2>/dev/null | grep '^name:' | awk '{print $2}')
                echo "✓ НАЙДЕНО: VM $vmid ($vm_name) на узле $node" > "$result_file"
                return 0
            fi
        done
    done

    if [ -s "$result_file" ]; then
        cat "$result_file"
    else
        echo "✗ Контейнер/VM с IP $TARGET_IP не найден в кластере"
        echo ""
        echo "Диагностика:"
        echo "1. Проверка доступности IP:"
        ping -c 1 -W 1 "$TARGET_IP" >/dev/null 2>&1 && echo "✓ IP доступен" || echo "✗ IP недоступен"

        echo "2. ARP запись:"
        arp -n | grep "$TARGET_IP" || echo "   Нет записи в ARP"

        echo "3. Проверка на узлах:"
        for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
            echo "   Узел $node:"
            ssh $node "ip route get $TARGET_IP 2>/dev/null" | grep -q "$TARGET_IP" && echo "   ✓ Маршрут существует" || echo "   ✗ Маршрута нет"
        done
    fi

    rm -f "$result_file"
}

find_container_by_ip "$@"

