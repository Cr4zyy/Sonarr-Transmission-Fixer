#!/bin/bash
#
# A simple script for Sonarr to run on download completion
# Lets Sonarr handle copying of the downloaded file and then
# updates the location of the seeded file for Transmission
# and finally removes the original downloaded file
#

#VARIABLES
REMOTE="transmission-remote -n USER:PASSWD" #Change USER and PASSWD
DEST="${sonarr_series_path}"
SPATH="${sonarr_episodefile_relativepath}"
TORRENT_NAME="${sonarr_episodefile_scenename}"
TORRENT_ID="${sonarr_download_id}"
STORED_FILE="${sonarr_episodefile_path}"
ORIGIN_FILE="${sonarr_episodefile_sourcepath}"
DT=$(date '+%Y-%m-%d %H:%M:%S')
SOURCEDIR="${sonarr_episodefile_sourcefolder}"
LOG=$(dirname $0)
LOG+="/sonarrtransmissionfixer.log"

if [ -e "$STORED_FILE" ]
then
    printf '%s | INFO  | Processing new download of: %s\n' "$DT" "${sonarr_series_title}" >> "$LOG"
    printf '%s | INFO  | Torrent ID: %s | Torrent Name: %s\n' "$DT" "$TORRENT_ID" "$TORRENT_NAME" >> "$LOG"
    SPATH=$(echo "${SPATH%/*}")
    DEST+="/$SPATH"
    printf '%s | INFO  | Season folder detected as: %s\n' "$DT" "$SPATH" >> "$LOG"
    #-t TorrentID --find NewTorrentDataLocation
    $REMOTE -t "$TORRENT_ID" --find "$DEST"
    printf '%s | INFO  | Torrent ID: %s, data now in: %s\n' "$DT" "$TORRENT_ID" "$STORED_FILE" >> "$LOG"

    if [ -e "$ORIGIN_FILE" ]
    then
        rm -f "$ORIGIN_FILE"
        printf '%s | INFO  | Deleting origin file: %s from %s\n' "$DT" "$TORRENT_NAME" "$SOURCEDIR" >> "$LOG"
    else
        printf '%s | ERROR | No origin file found to remove for: %s\n' "$DT" "$TORRENT_NAME" >> "$LOG"
    fi
else
    if [ -e "$ORIGIN_FILE" ]
    then
        printf '%s | ERROR | Stored file not located in: %s\n' "$DT" "$STORED_FILE" >> "$LOG"
        printf '%s | ERROR | Not moving torrent file for: %s\n' "$DT" "$TORRENT_NAME" >> "$LOG"
    else
        printf '%s | ERROR | No file exists to move or find!\n' "$DT" >> "$LOG"
    fi
fi

#Log upto a maximum of 100 lines
LINECOUNT=$(wc -l < $LOG)
if (( $(echo "$LINECOUNT > 100"| bc -l) )); then
    echo "$(tail -100 $LOG)" > "$LOG"
fi
