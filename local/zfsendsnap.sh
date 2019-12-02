#!/bin/bash

set -e
set -o pipefail

DATASET='zroot/home'

lockfile=/etc/systemd/zfs/zfsendsnap.lock
lastfile=/etc/systemd/zfs/zfsendsnap.last
pid=$(cat $lockfile 2>/dev/null || true)

if [ "x$pid" != "x" ]; then
  if kill -0 "$pid" 2>/dev/null; then
    echo "Another zfsendsnap.sh running." >&2
    exit 1
  fi
fi
echo "$$" > "$lockfile"

last=$(cat $lastfile)

now=$(date +replica-%Y-%m-%d_%H.%M.%S)
echo $last ... $now

zfs snapshot "${DATASET}@${now}"
zfs send -R -I "@${last}" "${DATASET}@${now}" | gzip | netcat -N mike 3010 | grep -q done

echo "${now}" > $lastfile

# exclude replica-from for now...
zfs list -t snapshot -o name -r ${DATASET} | grep '@replica-' | grep -v replica-from | sed -e "/${now}/"',$d' | while read x; do
  echo "zfs destroy $x"
  zfs destroy "$x"
done

rm -f $lockfile
