#!/bin/bash

TARGET_IP="${1:-192.168.87.209}"

echo "Расширенный поиск устройства с IP: $TARGET_IP"
echo "=============================================="

# Получаем MAC адрес из таблицы соседей
NEIGH_INFO=$(ip neigh show | grep "$TARGET_IP")
if [ -z "$NEIGH_INFO" ]; then
    echo "✗ IP не найден в таблице соседей"
    exit 1
fi

MAC=$(echo "$NEIGH_INFO" | awk '{print $5}')
INTERFACE=$(echo "$NEIGH_INFO" | awk '{print $3}')
STATE=$(echo "$NEIGH_INFO" | awk '{print $6}')

echo "✓ Найдена запись:"
echo "  IP:        $TARGET_IP"
echo "  MAC:       $MAC"
echo "  Интерфейс: $INTERFACE"
echo "  Статус:    $STATE"
echo ""

# Определяем производителя по OUI MAC адреса
echo "Информация о производителе:"
OUI=$(echo "$MAC" | cut -d: -f1-3 | tr '[:lower:]' '[:upper:]')
case $OUI in
    "BC:24:11") echo "  ✓ QEMU Virtual Machine/Контейнер" ;;
    "52:54:00") echo "  ✓ QEMU/KVM Virtual Machine" ;;
    "00:16:3E") echo "  ✓ Xen Virtual Machine" ;;
    "0A:00:27") echo "  ✓ VirtualBox" ;;
    "00:50:56") echo "  ✓ VMware" ;;
    "00:1C:42") echo "  ✓ Parallels" ;;
    *) echo "  ? Производитель: $OUI (возможно, физическое устройство)" ;;
esac
echo ""

# Поиск на узлах Proxmox по MAC адресу
echo "Поиск в кластере Proxmox:"
echo "=========================="

FOUND=0
for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
    echo "Узел: $node"

    # Поиск в VM по MAC адресу
    VM_LIST=$(ssh $node "qm list" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$VM_LIST" | awk 'NR>1 {print $1}' | while read vmid; do
            [ -z "$vmid" ] && continue

            # Получаем MAC адреса VM
            VM_MACS=$(ssh $node "qm config $vmid" 2>/dev/null | grep -oE '([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}')
            for vm_mac in $VM_MACS; do
                if [ "$(echo $vm_mac | tr '[:upper:]' '[:lower:]')" = "$(echo $MAC | tr '[:upper:]' '[:lower:]')" ]; then
                    vm_name=$(ssh $node "qm config $vmid" 2>/dev/null | grep '^name:' | awk '{print $2}')
                    vm_status=$(ssh $node "qm status $vmid" 2>/dev/null | grep 'status:' | awk '{print $2}')
                    echo "✓ НАЙДЕНО: VM $vmid ($vm_name) - статус: $vm_status"
                    FOUND=1
                fi
            done
        done
    fi

    # Поиск в CT через сетевые интерфейсы
    CT_LIST=$(ssh $node "pct list" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$CT_LIST" | awk 'NR>1 {print $1}' | while read ctid; do
            [ -z "$ctid" ] && continue

            # Ищем veth интерфейс контейнера
            VETH_INTERFACE="veth$ctid"
            VETH_MAC=$(ssh $node "ip link show $VETH_INTERFACE 2>/dev/null" | grep -oE 'link/ether [a-f0-9:]+' | cut -d' ' -f2)

            if [ "$(echo $VETH_MAC | tr '[:upper:]' '[:lower:]')" = "$(echo $MAC | tr '[:upper:]' '[:lower:]')" ]; then
                ct_name=$(ssh $node "pct config $ctid" 2>/dev/null | grep '^hostname:' | awk '{print $2}')
                ct_status=$(ssh $node "pct status $ctid" 2>/dev/null | grep 'status:' | awk '{print $2}')
                echo "✓ НАЙДЕНО: CT $ctid ($ct_name) - статус: $ct_status"
                FOUND=1
            fi
        done
    fi

    # Поиск на bridge интерфейсах
    for bridge in $(ssh $node "ls /sys/class/net/ | grep -E '^br|^vmbr'" 2>/dev/null); do
        BRIDGE_INFO=$(ssh $node "brctl show $bridge 2>/dev/null")
        if echo "$BRIDGE_INFO" | grep -qi "$MAC"; then
            echo "✓ MAC найден на bridge: $bridge"
            # Показываем связанные интерфейсы
            echo "$BRIDGE_INFO" | grep -v "bridge name" | while read line; do
                if echo "$line" | grep -q "$MAC"; then
                    INTERFACE=$(echo "$line" | awk '{print $4}')
                    echo "  → Интерфейс: $INTERFACE"
                fi
            done
        fi
    done
done

echo ""
echo "Дополнительная информация:"
echo "=========================="

# Проверяем, к какому bridge подключен интерфейс
BRIDGE_INFO=$(brctl show | grep "$INTERFACE")
if [ -n "$BRIDGE_INFO" ]; then
    BRIDGE_NAME=$(echo "$BRIDGE_INFO" | awk '{print $1}')
    echo "✓ Интерфейс $INTERFACE подключен к bridge: $BRIDGE_NAME"
fi

# Сканируем устройство
echo ""
echo "Сканирование устройства $TARGET_IP:"
nmap -sS -O --host-timeout 30s $TARGET_IP 2>/dev/null | grep -E 'MAC Address|Running|open' | head -10

if [ $FOUND -eq 0 ]; then
    echo ""
    echo "Вывод:"
    echo "======="
    echo "Устройство с IP $TARGET_IP и MAC $MAC НЕ является контейнером или VM"
    echo "в текущем кластере Proxmox."
    echo ""
    echo "Вероятно, это:"
    echo "- Физический сервер"
    echo "- Docker контейнер на физической машине"
    echo "- Устройство в другой сети (роутер, коммутатор)"
    echo "- VM на другом гипервизоре (ESXi, Hyper-V, VirtualBox)"
    echo "- Сетевое устройство или appliance"
fi

