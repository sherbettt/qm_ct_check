for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
  echo "=== VM на узле: $node ==="
  ssh $node "qm list"
done

echo " "
echo "=================="
echo " "

for node in $(pvecm nodes | awk '{print $3}' | grep -v Name); do
  echo "=== CT на узле: $node ==="
  ssh $node "pct list"
done
