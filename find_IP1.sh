#!/bin/bash

TARGET_IP="${1:-192.168.87.209}"

echo "Поиск контейнера/VM с IP: $TARGET_IP"
echo "======================================"

# Проверяем, может быть это физический сервер или внешний хост
echo "1. Проверка доступности и диагностика:"
ping -c 1 -W 1 "$TARGET_IP" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ IP доступен"

    # Смотрим ARP запись
    echo "2. ARP запись:"
    arp_entry=$(arp -n | grep "$TARGET_IP")
    if [ -n "$arp_entry" ]; then
        echo "   $arp_entry"
        MAC=$(echo "$arp_entry" | awk '{print $3}')
        echo "   MAC адрес: $MAC"

        # Ищем интерфейс с этим MAC
        echo "3. Поиск интерфейса:"
        for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
            interface=$(ssh $node "ip link show" 2>/dev/null | grep -B1 -i "$MAC" | head -1 | grep -oP '^\d+:\s+\K[^:]+')
            if [ -n "$interface" ]; then
                echo "   ✓ Найден на узле $node: интерфейс $interface"

                # Если это veth интерфейс, пытаемся найти CT
                if echo "$interface" | grep -q 'veth'; then
                    ctid=$(echo "$interface" | sed 's/veth//')
                    # Проверяем, является ли ctid числом
                    if [ "$ctid" -eq "$ctid" ] 2>/dev/null; then
                        ct_name=$(ssh $node "pct config $ctid" 2>/dev/null | grep '^hostname:' | awk '{print $2}')
                        if [ -n "$ct_name" ]; then
                            echo "   ✓ Это CT $ctid ($ct_name)"
                        fi
                    fi
                fi
            fi
        done
    else
        echo "   Нет записи в ARP - возможно, это не в локальной сети"
    fi
else
    echo "✗ IP недоступен"
    exit 1
fi

echo ""
echo "4. Подробный поиск по кластеру:"

FOUND=0
for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
    # Быстрый поиск в CT
    result=$(ssh $node "pct list" 2>/dev/null | awk 'NR>1 {print $1}' | while read ctid; do
        ip=$(ssh $node "pct exec $ctid hostname -I 2>/dev/null" | xargs echo)
        if echo " $ip " | grep -q " $TARGET_IP "; then
            ct_name=$(ssh $node "pct config $ctid" 2>/dev/null | grep '^hostname:' | awk '{print $2}')
            echo "✓ НАЙДЕНО: CT $ctid ($ct_name) на узле $node"
            echo "FOUND" > /tmp/found_$$.txt
        fi
    done)

    if [ -n "$result" ]; then
        echo "$result"
        FOUND=1
    fi

    # Поиск в VM
    result=$(ssh $node "qm list" 2>/dev/null | awk 'NR>1 {print $1}' | while read vmid; do
        ip=$(ssh $node "qm guest cmd $vmid network-get-interfaces 2>/dev/null" | grep -oP '"ip-address":"\K[^"]+' | head -1)
        if [ "$ip" = "$TARGET_IP" ]; then
            vm_name=$(ssh $node "qm config $vmid" 2>/dev/null | grep '^name:' | awk '{print $2}')
            echo "✓ НАЙДЕНО: VM $vmid ($vm_name) на узле $node"
            echo "FOUND" > /tmp/found_$$.txt
        fi
    done)

    if [ -n "$result" ]; then
        echo "$result"
        FOUND=1
    fi
done

if [ $FOUND -eq 0 ]; then
    echo "✗ Не найден в кластере Proxmox"
    echo "Возможные причины:"
    echo "- Физический сервер"
    echo "- Контейнер/VM на другом кластере"
    echo "- Сетевое оборудование"
    echo "- Внешний хост"
fi

rm -f /tmp/found_$$.txt

