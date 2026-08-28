# Посмотреть все контейнеры с включенным автозапуском
for ct in $(pct list | tail -n +2 | awk '{print $1}'); do
  onboot=$(pct config $ct 2>/dev/null | grep "onboot:" | awk '{print $2}')
  if [ "$onboot" = "1" ]; then
    status=$(pct status $ct | awk '{print $2}')
    name=$(pct config $ct | grep "hostname:" | awk '{print $2}')
    echo "CT $ct ($name): onboot=$onboot, status=$status"
  fi
done
