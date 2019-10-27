# Nextcloud S3 Glacier cron Archiver

This program automates a nextcloud instance's backup with [S3 Glacier](https://aws.amazon.com/glacier/) upload. Daily archives are made with weekly, monthly and yearly rotations. The idea is to keep useful archives at significant times.

## Prerequisites

This program is made for [nextcloud-snap](https://github.com/nextcloud/nextcloud-snap) instances as it relies on `nextcloud.export` tool.

It depends on `jq`, `openssl`, `parallel` and `xz-utils` (for optimal compression). On debian-based distros:
```
sudo apt install jq openssl parallel xz-utils
```

Finally, [it uses AWS official client so please refer to their documentation for installation](https://github.com/aws/aws-cli).

## Installation

Make sure [AWS CLI is properly configured with your credentials](https://github.com/aws/aws-cli#getting-started).

Then clone this repository and setup a cron job for a daily backup.

You can edit root's crontab with this command:
```bash
sudo crontab -e
```

And then add the following cron line for the root user:
```
0 5 * * * env "PATH=$PATH:/path/to/aws/bin:/snap/bin" /path/to/nextcloud-to-glacier/nextcloud-cron-backup-aws.sh &>> /path/to/nextcloud-to-glacier/nextcloud-to-glacier.log
```

_NB:_
- `/path/to/aws/bin` depends on your installation. For me it was `/home/myuser/.local/bin`
- Make sure to replace `/path/to/nextcloud-s3-glacier-backup` by **an absolute path without `~`**.
- Make sure you also did the above for the log file (second occurence in the cron line)
- "5" on the cron line hold the hour position and means the script runs everyday at 5am. You can obviously adjust it! :)

## Backup restoration

This part has not been automated, however you can download the glacier archive manually and restore it with the following steps:
```
tar -xf backup.tar.xz
# Either use nextcloud-snap's importer
nextcloud.import extracted_backup_folder
# Or import desired data manually from the folder, for ex.:
nextcloud.mysql -u nextcloud -p nextcloud < extracted_backup_folder/database.sql
# Password can be looked up in extracted_backup_folder/config.php
```

## Credits

AWS tree hash signature relies on [Thomas Baier's tool](https://github.com/numblr/glaciertools) which we should be grateful for!
