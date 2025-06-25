#!/bin/bash

# Backup user Cron jobs
crons="/home/$USER/bin/cronjobs.cnf"
echo "Exporting user cron jobs into $crons"
crontab -l -u $USER > "$crons" 2>&1 # must be privileged user to use this form
# crontab -l > "$crons" 2>&1 # when running with sudo, we get root jobs only (empty)
LASTERR=$?
if [[ $LASTERR == 0 ]]; then
    echo "Done."
else
    echo "Empty cron."
fi

# export the list of installed packages
if [ -f /etc/os-release ]; then
    source /etc/os-release

    case $ID in
        fedora)
            rpms="/home/$USER/bin/rpm.list"
            echo "Exporting installed packages into $rpms"
            rpm -qa | sort > "$rpms" 2>&1
            echo "Done."
            ;;
        debian)
            pkgs="/home/$USER/bin/pkgs.list"
            echo "Exporting installed packages into $pkgs"
            dpkg -l > "$pkgs" 2>&1
            echo "Done."
            ;;
    esac
fi

#export the Flatpak installed apps
if command -v flatpak 2>&1 >/dev/null
then
    flatpaks="/home/$USER/bin/flatpaks.list"
    echo "Exporting the Flatpak installed apps into $flatpaks"
    sudo -u $USER flatpak list > "$flatpaks" 2>&1
    echo "Done."
fi

# return a non-zero value to abort the main backup
# exit 42
