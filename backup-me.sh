#!/bin/bash
# Wrapper for borg backup
# (c) 2019,2020,2025 Sébastien KIRCHE

# abort in case of failing piped command
set -Euo pipefail
# call a cleanup function in case of terminating signal
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd -P -- "$(dirname -- "$(realpath "$(command -v -- "$0")")" )" && pwd -P)

default_config="$script_dir/backup-me.env"
backup_list="$script_dir/backup-me.lst"
BACKNAME='{fqdn}-{now:%Y-%m-%d}'
PRE_BACKUP="$script_dir/backup-me-first.sh"

# declare variables for term colors
setup_colors() {
    if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
        NOFORMAT='\033[0m' BOLD='\033[1m'
        RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[0;33m' WHITE='\033[0;37m'
        BRED='\033[0;31m' BGREEN='\033[0;32m' BORANGE='\033[0;33m' BBLUE='\033[0;34m' BPURPLE='\033[0;35m' BCYAN='\033[0;36m' BYELLOW='\033[0;33m' BWHITE='\033[0;37m'
    else
        NOFORMAT='' BOLD='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW='' WHITE=''
    fi
}

# need to call func before using color variables
setup_colors

# Change the color meaning here
ERRFMT=$RED
WARNFMT=$ORANGE
OKFMT=$GREEN
SETTINGFMT=$CYAN
HIGLIGHTFMT=$WHITE

# show the parameters accepted by the script
usage() {
    local txt=$(cat <<USAGE
${HIGLIGHTFMT}Usage:${NOFORMAT} $(basename "${BASH_SOURCE[0]}") [-h] [-u USER] [-r REPO] [-p passphrase] [--compress lz4] [-a action-file] [-n archive_name_pattern] [-c comment]

${HIGLIGHTFMT}Available options:${NOFORMAT}
-u, --user                 name of the USER for whom we want to backup
-r, --repo, --repository   location to the Borg destination repository
-l, --list                 location of the list of files/directory to process
-n, --name                 pattern used for backup name (default is ${SETTINGFMT}$BACKNAME${NOFORMAT})
-p, --passphrase           passphrase used to acces the repository
-a, --actions              actions to run before backup (default is ${SETTINGFMT}$PRE_BACKUP${NOFORMAT})
-c, --comment              put a comment for the backup
    --compress             default compression (none, zstd, zlib, lz4)
-h, --help                 Print this help and exit

Default list to backup will be read from ${SETTINGFMT}$backup_list${NOFORMAT}

${HIGLIGHTFMT}Notes on borg repo creation:${NOFORMAT} repo MUST exist berfore creating the first backup.
- unencrypted (clear data blocks hashed in SHA256):
  borg init --encryption=none /path/to/repo
- authenticated (but not encrypted, use repokey and key file:
  borg init --encryption=authenticated /path/to/repo
- encrypted using passphrase (repokey mode, random key is stored in the repo config file):
  borg init --encryption=repokey /path/to/local/repo
  borg init --encryption=repokey user@host:path/to/remote/repo 
  borg init --encryption=repokey-blake2 /path/to/repo # HMAC-BLAKE2b often faster since v1.1
- encrypted using passphrase + key file (keyfile mode, key is stored in ~/.config/borg/keys
                                         any access to the repo need the key file)
  borg init --encryption=keyfile user@host:backuprepo

USAGE
          )
    msg "$txt"
}

# function called in case of interrution signal or script termination
cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
    # unexport variables
    export -n BORG_PASSPHRASE
    export -n BORG_CACHE_DIR
}  

# remove color codes to get text only
decolorize(){
    echo -e "$1" | sed -r 's/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g'
}

# print a message on standard error, honoring colors if any
msg() {
    echo >&2 -e "${1-}"
}

# print a fatal message then suicide with status code (default is 1)
die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    msg "$msg"
    exit "$code"
}

SIMULATE=''
COMMENT=''

# parse script params. I could use getopt but it does not handle long params
parse_params() {
    while :; do
        case "${1-}" in
            -u | --user) USER="${2-}"
                         shift
                         ;;
            -r | --repo | --repository) REPOSITORY="${2-}"; shift ;;
            -l | --list) backup_list="${2-}"; shift ;;
            -n | --name) BACKNAME="${2-}"; shift ;;
            -p | --passphrase) export BORG_PASSPHRASE="${2-}"; shift ;;
                 --compress) COMPRESSION="${2-}"; shift ;;
            -c | --comment) COMMENT="${2-}"; shift ;;
            -a | --action) PRE_BACKUP="${2-}"; shift ;;
            -s | --simulate) SIMULATE=" --list --dry-run" ;;
            -h | --help) usage; exit 0 ;;
            -v | --verbose) set -x ;;
            --no-color) NO_COLOR=1 ;;
            -?*) die "Unknown option: $1" ;;
            *) break ;;
        esac
        shift
    done

    args=("$@")

    # check required params and arguments
    # [[ -z "${param-}" ]] && die "${ERRFMT}Missing required parameter${NOFORMAT}: param"
    # [[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"
    
    return 0
}

if [ -f $default_config ]; then
    source $default_config
fi

setup_colors
parse_params "$@"

if [[ -z $USER ]]; then
    die "No value for variable USER. Please define it in $default_config or call $0 with --user" 1
fi
if [[ -z $REPOSITORY ]]; then
    die "No value for variable REPOSITORY. Please define it in $default_config or call $0 with --repository" 1
fi
if [[ -z "$BORG_PASSPHRASE" ]]; then
   die "No value for variable BORG_PASSPHRASE. Please define it in $default_config or call $0 with --passphrase" 1
fi
if [[ -z "$COMPRESSION" ]]; then
   COMPRESSION=lz4
fi
if [[ ! -r "$backup_list" ]]; then
    die "Cannot read processing list $backup_list" 2
fi

# force usage of user cache in case borg is called from sudo
export BORG_CACHE_DIR=/home/$USER/.cache/borg

date '+%+4Y-%m-%d %H:%M:%S'     # show a timestamp (useful for logs)
echo "Called with: $0 $@"

# TODO: Sanity check: test if backup device is mounted
#if ! mountpoint -q $(dirname $REPOSITORY); then  <== this is not working for remote ssh
#    echo Backup device is not mounted!
#    exit 1
#fi

if [[ ! $REPOSITORY == *@*:* ]]; then # do not test remote repositories
    if [[ ! -d "$REPOSITORY" ]]; then
        die "Repository $REPOSITORY does not exist. External device not mounted?" 3
    fi
    if [[ ! -w "$REPOSITORY" ]]; then
        die "Repository $REPOSITORY is not writable by you" 3
    fi
fi

################################################################################
# Preliminary actions
if [[ -x "$PRE_BACKUP" ]]; then
    msg "${WHITE}Performing pre-backup actions${NOFORMAT} from $script_dir/backup-me-first.sh..."
    "$PRE_BACKUP"
    if [[ $? -ne 0 ]]; then
        die "${ERRFMT}Pre-backup script returned a non-zero value.${NOFORMAT}" 4
    fi
    msg "${OKFMT}Pre-backup actions done.${NOFORMAT}"
elif [[ -f "$PRE_BACKUP" ]]; then
    die "Pre-backup actions $PRE_BACKUP exists but is not executable" 5
else
    msg "No pre-backup action file defined."
fi
################################################################################

msg "Backup in $REPOSITORY using definition list $backup_list"
msg "Backup will be named using '${SETTINGFMT}$BACKNAME${NOFORMAT}'."
msg "Using compression ${SETTINGFMT}$COMPRESSION${NOFORMAT}"
msg "Starting backup..."

################################################################################
# Perform Backup
borg create -v --stats --show-rc                 \
     --compression $COMPRESSION                  \
     $REPOSITORY::"$BACKNAME"                    \
     --patterns-from "$backup_list"              \
     $SIMULATE                                   \
     ${COMMENT:+"--comment=$COMMENT"}            \
     2>&1

# instead of --pattern-from you can use hard-coded path to add or exclude:
    # /home/$USER/                                \
    # /etc                                        \
    # --exclude '/home/*/.cache'                  \
    # --exclude '/home/*/.svn'                    

# used to have --progress, but it generates much too long logs
# you can force a specific backup date with --timestamp 2022-03-21T20:00:00
     # --timestamp 2022-03-21T20:00:00  


################################################################################
# Notify the backup result to the user
BACKUPERR=$?
# echo Backup finished with $BACKUPERR
PRUNE_REPO=0
if [[ $BACKUPERR == 0 ]]; then
    PRUNE_REPO=1                # clean repo only if all was OK
    MSG="$(date -Iminutes) - ${OKFMT}Backup succeeded${NOFORMAT}."
    msg $MSG
    MSG=$(decolorize "$MSG")
    ICON=${ICON_OK-}
    [[ $(type -t _backup_custom_notify) == function ]] && _backup_custom_notify "$MSG" $ICON green
elif [[ $BACKUPERR == 1 ]]; then
    MSG="$(date -Iminutes) - ${WARNFMT}Backup completed with warnings${NOFORMAT}... See log (or root's dead.letter) for details."
    msg $MSG
    MSG=$(decolorize "$MSG")
    ICON=${ICON_WARNING-}
    [[ $(type -t _backup_custom_notify) == function ]] && _backup_custom_notify "$MSG" $ICON yellow
elif [[ $BACKUPERR == 2 ]]; then
    MSG="$(date -Iminutes) - ${ERRFMT}Backup failed?!!${NOFORMAT} See log (or root's dead.letter) for details."
    msg $MSG
    MSG=$(decolorize "$MSG")
    ICON=${ICON_ERROR-}
    [[ $(type -t _backup_custom_notify) == function ]] && _backup_custom_notify "$MSG" $ICON red
else
    signal=$(($BACKUPERR-128))
    MSG="$(date -Iminutes) - ${PURPLE}Backup killed${NOFORMAT} with -${signal}!"
    msg $MSG
    MSG=$(decolorize "$MSG")
    ICON=${ICON_ERROR-}
    [[ $(type -t _backup_custom_notify) == function ]] && _backup_custom_notify "$MSG" $ICON red
    exit $BACKUPERR
fi

################################################################################
# Use the "prune" subcommand to keep some daily, weekly and monthly
# archives of THIS machine. The '{fqdn}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machine's archives also.
if [[ "$PRUNE_REPO" == "1" ]]; then
    echo "Pruning the repository..."
    borg prune -v --list             \
         $REPOSITORY                 \
         --glob-archives '{fqdn}-*'  \
         --keep-daily=7              \
         --keep-weekly=6             \
         --keep-monthly=12
else
    msg "${ERRFMT}Skipping repository pruning due to problems.${NOFORMAT}"
fi
echo "Done."

# next line is some settings for vi 
# ex: ts=4 sw=4 sts=4 et :
