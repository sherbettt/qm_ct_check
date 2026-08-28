#!/bin/bash

VM_ID=$1

if [ -z "$VM_ID" ]; then
    echo "Ошибка: Укажите ID контейнера"
    echo "Использование: $0 <VM_ID>"
    exit 1
fi

echo "Поиск бэкапов для контейнера $VM_ID"
echo "=========================================="

# Поиск на локальной ноде
echo "Локальная нода ($(hostname)):"
find /stg/ -name "vzdump-lxc-${VM_ID}-*.tar.zst" 2>/dev/null | sort -r

# Поиск на других нодах из /etc/hosts
for node in prox4 pmx6 pmx7; do
    if [ "$node" != "$(hostname)" ]; then
        echo ""
        echo "Нода $node:"
        ssh -o ConnectTimeout=3 "root@${node}" \
            "find /stg/ -name 'vzdump-lxc-${VM_ID}-*.tar.zst' 2>/dev/null | sort -r" 2>/dev/null
    fi
done

echo ""
echo "=========================================="
echo "Поиск завершен"

