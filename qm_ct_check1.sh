# Генерируем последовательность чисел, например, от 100 до 2000
seq 100 350 > all_possible_ids.txt

# Записываем все занятые ID
( for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do ssh $node "qm list" | awk 'NR>1 {print $1}'; done
  for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do ssh $node "pct list" | awk 'NR>1 {print $1}'; done
) | sort -n > used_ids.txt

# Ищем строки, которые есть в первом файле, но отсутствуют во втором (т.е. свободные ID)
comm -23 all_possible_ids.txt used_ids.txt | head -n 12
