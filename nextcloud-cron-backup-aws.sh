#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo
echo "$(date -Iseconds) Starting nextcloud backup to glacier"

nextcloud.export
cd /var/snap/nextcloud/common/backups
backup_name="$(ls -1t | head -1)"
backup_archive="/tmp/${backup_name}.tar.xz"

XZ_OPT=-0 tar cJf "${backup_archive}" "${backup_name}"
backup_size=$(wc -c < ${backup_archive})

echo "Will now upload ${backup_archive}"
aws glacier upload-archive \
  --vault-name NextcloudBackup \
  --account-id - \
  --archive-description "Nextcloud backup ${backup_name}" \
  --checksum $("$DIR/treehash.sh" "${backup_archive}") \
  --body "${backup_archive}" \
  | jq -r '.archiveId' >> "$DIR/archiveIds"

function check_and_rotate() {
  local source_file=$1
  local target_file=$2
  local number_in_period=$3
  local n_entries=$(wc -l $source_file | cut -d " " -f 1)

  if [ $number_in_period -eq 1 -a $n_entries -gt 0 ] ; then
    echo Rotating $source_file to $target_file
    tail -1 $source_file >> $target_file

    for archiveId in $(head -$(($n_entries - 1)) $source_file) ; do
      echo "Deleting archive ${archiveId}"
      aws glacier delete-archive \
        --vault-name NextcloudBackup \
        --account-id - \
	--archive-id $archiveId
    done

    printf "" > $source_file
  fi
}

check_and_rotate "$DIR/archiveIds" "$DIR/archiveIdsWeek" $(date '+%u')
check_and_rotate "$DIR/archiveIdsWeek" "$DIR/archiveIdsMonth" $(date '+%d')
check_and_rotate "$DIR/archiveIdsMonth" "$DIR/archiveIdsYear" $(date '+%m')

rm -rf "${backup_archive}" "${backup_name}"
echo "Backup success"
