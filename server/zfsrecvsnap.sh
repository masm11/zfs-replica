#!/bin/bash

set -e
set -o pipefail

DATASET='zbak/luna'

echo $DATASET >&2
zcat | zfs recv -v -F "${DATASET}" >&2

echo done
exit 0
