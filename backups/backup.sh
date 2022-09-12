#!/bin/bash
#################################################################
#                                                               #
# Takes folders in the services directory (all docker compose), #
# stops them, archives them, and then brings them back up,      #
# finally backing them up to the cloud.                         #
#                                                               #
#################################################################

# CONFIG

KEY_ID=[B2_KEYID]
APPLICATION_KEY=[B2_APPKEY]
BUCKET=[B2_BUCKET]

# END CONFIG

center() {
  termwidth="80"
  padding="$(printf '%0.1s' ={1..500})"
  printf '%*.*s %s %*.*s\n' 0 "$(((termwidth-2-${#1})/2))" "$padding" "$1" 0 "$(((termwidth-1-${#1})/2))" "$padding"}
}
echo "Beginning Docker backup @ `date`"
echo
BACKUPDIR="$HOME/backups/current/`date +"%Y-%m-%d"`"
mkdir $BACKUPDIR
echo Saving backed up archives to $BACKUPDIR

for d in $HOME/services/*/; do
    cd $d
    SERVICE=${PWD##*/}

    echo
    echo `center "$SERVICE"`
    echo

    if [ -f "_backup_sql.sh" ]; then
        ./_backup_sql.sh
    fi

    if [ -f "_docker_stop" ]; then
        echo Bring down $SERVICE
        docker-compose stop
    fi

    echo "Archiving directory to $BACKUPDIR/$SERVICE.tar.gz"

    cd ../
    sudo tar -czf "$BACKUPDIR/$SERVICE.tar.gz" "$SERVICE"
    sudo chown $USER:$USER "$BACKUPDIR/$SERVICE.tar.gz"

    cd $d
    if [ -f "_docker_stop" ]; then
        echo Bring back up $SERVICE

        cd $d
        docker-compose up -d
    fi

    if [ -f "_backup_sql.sh" ]; then
            rm backup.sql
    fi
    echo
    echo `center "FINISHED"`
done

echo
echo Archiving old files, nuking older files...
find $HOME/backups/current -mtime +3 -exec mv {} $HOME/archive \;
find $HOME/backups/archive -mtime +10 -exec rm -r {} \;
echo
echo Finished, syncing backup directory.
echo
backblaze-b2 authorize_account $KEY_ID $APPLICATION_KEY
backblaze-b2 sync --noProgress --compareVersions none --delete --replaceNewer $HOME/backups/current b2://$BUCKET
echo
echo "Finished @ `date`"
