# backup-me
My own used-to-be-simple BorgBackup wrapper

`backup-me.sh` is a convenient wrapper to Borg that allows routine pre-actions like exporting some data (package list, cron jobs, ...), performing some aging cleanup and notifying user with result.


`Usage: backup-me.sh [-h] [-u USER] [-r REPO] [-p passphrase] [--compress lz4] [-a action-file] [-n archive_name_pattern] [-c comment]

Available options:
-u, --user                 name of the USER for whom we want to backup
-r, --repo, --repository   location to the Borg destination repository
-l, --list                 location of the list of files/directory to process
-n, --name                 pattern used for backup name (default is {fqdn}-{now:%Y-%m-%d})
-p, --passphrase           passphrase used to acces the repository
-a, --actions              actions to run before backup (default is /home/seki/bin/backup-me/backup-me-first.sh)
-c, --comment              put a comment for the backup
    --compress             default compression (none, zstd, zlib, lz4)
-h, --help                 Print this help and exit
`

