#!/bin/bash

VM_ID=$1

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
UNDERLINE='\033[4m'

# Проверка аргументов
if [ -z "$VM_ID" ]; then
    echo -e "${RED}Ошибка: Укажите ID контейнера${NC}"
    echo "Использование: $0 <VM_ID> [--all-nodes] [--show-notes]"
    echo "  --all-nodes  - поиск на всех нодах кластера"
    echo "  --show-notes - показать содержимое .notes файлов (если есть)"
    exit 1
fi

# Параметры
SEARCH_ALL_NODES=false
SHOW_NOTES=false
for arg in "$2" "$3"; do
    if [ "$arg" == "--all-nodes" ]; then
        SEARCH_ALL_NODES=true
    elif [ "$arg" == "--show-notes" ]; then
        SHOW_NOTES=true
    fi
done

# Функция поиска на локальной ноде
search_local() {
    find /stg/ -name "vzdump-lxc-${VM_ID}-*.tar.zst" 2>/dev/null | sort -r
}

# Функция поиска на удаленной ноде
search_remote() {
    local node=$1
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${node}" \
        "find /stg/ -name 'vzdump-lxc-${VM_ID}-*.tar.zst' 2>/dev/null | sort -r" 2>/dev/null
}

# Получение списка нод кластера
get_cluster_nodes() {
    local current_node=$(hostname)
    local nodes=()
    
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+(.+)$ ]]; then
            node="${BASH_REMATCH[1]}"
            if [[ "$node" != "$current_node" && "$node" != *"(local)"* ]]; then
                node=$(echo "$node" | sed 's/\s*(local)//')
                nodes+=("$node")
            fi
        fi
    done < <(pvecm nodes 2>/dev/null | tail -n +4)
    
    echo "${nodes[@]}"
}

echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║${NC}        ${BOLD}Поиск бэкапов для LXC контейнера ${CYAN}${VM_ID}${NC}${BOLD} в Proxmox кластере${NC}                ${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}\n"

# Массивы для хранения результатов
declare -a all_backups
declare -a backup_sources
declare -a backup_has_notes
declare -a backup_notes_content

# Поиск на локальной ноде
echo -e "${CYAN}🔍 Поиск на локальной ноде: ${BOLD}$(hostname)${NC}..."
local_backups=()
while IFS= read -r backup; do
    [ -n "$backup" ] && local_backups+=("$backup")
done < <(search_local)

for backup in "${local_backups[@]}"; do
    all_backups+=("$backup")
    backup_sources+=("$(hostname)")
    
    # Проверяем наличие notes
    notes_path="${backup}.notes"
    if [ -f "$notes_path" ]; then
        backup_has_notes+=("yes")
        if [ "$SHOW_NOTES" = true ]; then
            notes_content=$(head -20 "$notes_path" 2>/dev/null)
            backup_notes_content+=("$notes_content")
        else
            backup_notes_content+=("")
        fi
    else
        backup_has_notes+=("no")
        backup_notes_content+=("")
    fi
done
echo -e "${GREEN}   Найдено: ${#local_backups[@]} бэкапов${NC}"

# Поиск на других нодах кластера
if [ "$SEARCH_ALL_NODES" = true ]; then
    echo -e "\n${CYAN}🔍 Получение списка нод кластера...${NC}"
    nodes=($(get_cluster_nodes))
    
    if [ ${#nodes[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠  Другие ноды кластера не найдены${NC}"
    else
        echo -e "${GREEN}   Найдено нод: ${#nodes[@]}${NC}"
        
        for node in "${nodes[@]}"; do
            echo -e "\n${CYAN}🔍 Поиск на ноде: ${BOLD}${node}${NC}..."
            remote_backups=()
            
            if ping -c 1 -W 2 "$node" &>/dev/null; then
                while IFS= read -r backup; do
                    [ -n "$backup" ] && remote_backups+=("$backup")
                done < <(search_remote "$node")
                
                if [ ${#remote_backups[@]} -gt 0 ]; then
                    echo -e "${GREEN}   ✅ Найдено: ${#remote_backups[@]} бэкапов${NC}"
                    for backup in "${remote_backups[@]}"; do
                        all_backups+=("$backup")
                        backup_sources+=("$node")
                        
                        # Проверяем наличие notes на удаленной ноде
                        notes_path="${backup}.notes"
                        has_notes=$(ssh -o ConnectTimeout=5 "root@${node}" \
                            "[ -f '$notes_path' ] && echo 'yes' || echo 'no'" 2>/dev/null)
                        
                        if [ "$has_notes" = "yes" ]; then
                            backup_has_notes+=("yes")
                            if [ "$SHOW_NOTES" = true ]; then
                                notes_content=$(ssh -o ConnectTimeout=5 "root@${node}" \
                                    "head -20 '$notes_path' 2>/dev/null" 2>/dev/null)
                                backup_notes_content+=("$notes_content")
                            else
                                backup_notes_content+=("")
                            fi
                        else
                            backup_has_notes+=("no")
                            backup_notes_content+=("")
                        fi
                    done
                else
                    echo -e "${YELLOW}   ❌ Бэкапы не найдены${NC}"
                fi
            else
                echo -e "${RED}   ⚠  Нода ${node} недоступна${NC}"
            fi
        done
    fi
else
    echo -e "\n${YELLOW}💡 Для поиска на всех нодах кластера используйте: $0 ${VM_ID} --all-nodes${NC}"
fi

# Объединение и сортировка всех найденных бэкапов
mapfile -t sorted_backups < <(printf "%s\n" "${all_backups[@]}" | sort -r)
count=${#sorted_backups[@]}

if [ $count -eq 0 ]; then
    echo -e "\n${RED}❌ Бэкапы для контейнера $VM_ID не найдены ни на одной ноде${NC}"
    exit 1
fi

# Сортируем также источники, has_notes и notes_content в том же порядке
declare -a sorted_sources
declare -a sorted_has_notes
declare -a sorted_notes_content

for backup in "${sorted_backups[@]}"; do
    for i in "${!all_backups[@]}"; do
        if [ "${all_backups[$i]}" = "$backup" ]; then
            sorted_sources+=("${backup_sources[$i]}")
            sorted_has_notes+=("${backup_has_notes[$i]}")
            sorted_notes_content+=("${backup_notes_content[$i]}")
            break
        fi
    done
done

# Вывод результатов
echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║${NC}                          ${BOLD}${GREEN}РЕЗУЛЬТАТЫ ПОИСКА${NC}                                  ${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}\n"

for i in "${!sorted_backups[@]}"; do
    backup="${sorted_backups[$i]}"
    source_node="${sorted_sources[$i]}"
    has_notes="${sorted_has_notes[$i]}"
    notes_content="${sorted_notes_content[$i]}"
    num=$((i+1))
    
    # Получение информации о файле
    if [ "$source_node" == "$(hostname)" ]; then
        size=$(du -h "$backup" 2>/dev/null | cut -f1)
        date_modified=$(date -r "$backup" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    else
        size=$(ssh -o ConnectTimeout=5 "root@${source_node}" "du -h '${backup}' 2>/dev/null | cut -f1" 2>/dev/null)
        date_modified=$(ssh -o ConnectTimeout=5 "root@${source_node}" "date -r '${backup}' '+%Y-%m-%d %H:%M:%S' 2>/dev/null" 2>/dev/null)
        [ -z "$size" ] && size="N/A"
        [ -z "$date_modified" ] && date_modified="N/A"
    fi
    
    # Определение цвета и метки свежести
    if [ $i -eq 0 ]; then
        prefix="${GREEN}★${NC}"
        color="${GREEN}"
        fresh=" ${GREEN}[САМЫЙ СВЕЖИЙ]${NC}"
    else
        prefix="${YELLOW}•${NC}"
        color="${YELLOW}"
        fresh=""
    fi
    
    # Обработка notes
    if [ "$has_notes" = "yes" ]; then
        notes_status="${GREEN}✓${NC} ${CYAN}есть .notes файл${NC}"
        
        # Если нужно показать содержимое и оно не пустое
        if [ "$SHOW_NOTES" = true ] && [ -n "$notes_content" ]; then
            # Экранируем специальные символы и форматируем
            notes_status="${notes_status}\n     ${BLUE}📝 Содержимое .notes:${NC}"
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    notes_status="${notes_status}\n     ${WHITE}   └─ ${line}${NC}"
                fi
            done <<< "$notes_content"
        fi
    else
        notes_status="${YELLOW}✗${NC} ${CYAN}нет .notes файла${NC}"
    fi
    
    # Вывод
    echo -e "${BOLD}${color}[${num}]${NC} ${prefix} ${BOLD}${color}${date_modified}${NC} | ${BLUE}Размер:${NC} ${CYAN}${size}${NC} | ${MAGENTA}Нода:${NC} ${BOLD}${source_node}${NC}${fresh}"
    echo -e "     ${BLUE}📁 Путь:${NC} ${color}${backup}${NC}"
    echo -e "     ${BLUE}📋 Notes:${NC} ${notes_status}"
    
    if [ $i -lt $((count-1)) ]; then
        echo -e "     ${BLUE}────────────────────────────────────────────────────────────────────────${NC}"
    fi
done

# Подсчет уникальных нод
unique_nodes=$(printf '%s\n' "${sorted_sources[@]}" | sort -u | wc -l)

echo -e "\n${BOLD}${GREEN}✅ Всего найдено: ${YELLOW}$count${NC} ${GREEN}бэкапов${NC} на ${MAGENTA}${unique_nodes}${NC} ${GREEN}нодах${NC}"
echo -e "${BOLD}${GREEN}📌 Самый свежий:${NC} ${YELLOW}${sorted_backups[0]}${NC} ${GREEN}(нода: ${MAGENTA}${sorted_sources[0]}${GREEN})${NC}"

if [ "$SHOW_NOTES" = true ]; then
    echo -e "\n${CYAN}💡 Показано содержимое .notes файлов (первые 20 строк)${NC}"
else
    echo -e "\n${YELLOW}💡 Для просмотра содержимого .notes файлов используйте: $0 ${VM_ID} --all-nodes --show-notes${NC}"
fi

echo ""
