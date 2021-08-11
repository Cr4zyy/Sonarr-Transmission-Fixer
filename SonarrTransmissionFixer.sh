#!/bin/bash
#
# A simple script for Sonarr to run on download completion
# Lets Sonarr handle copying of the downloaded file and then
# updates the location of the seeded file for Transmission
# and finally removes the original downloaded file
#

#VARIABLES
REMOTE="transmission-remote -n USER:PASSWD" #Change USER and PASSWD
DLDIR="sonarr" #Name of the folder sonarr downlaods all torrents into, can be customised with 'Category' option in download client options


DEST="${sonarr_series_path}"
SPATH="${sonarr_episodefile_relativepath}"
TORRENT_NAME="${sonarr_episodefile_scenename}"
TORRENT_ID="${sonarr_download_id}"
STORED_FILE="${sonarr_episodefile_path}"
ORIGIN_FILE="${sonarr_episodefile_sourcepath}"
EVENTTYPE="${sonarr_eventtype}"
SOURCEDIR="${sonarr_episodefile_sourcefolder}"

SPATH=$(echo "${SPATH%/*}")
DEST+="/$SPATH"
TORRENT_DIR=$(basename "$SOURCEDIR")
TDEST="$DEST/$TORRENT_DIR"

DT=$(date '+%Y-%m-%d %H:%M:%S')
LOG=$(dirname $0)
LOG+="/sonarrtransmissionfixer.log"

printferr() { printf '%s\n' "$@" 1>&2; }

if [[ "$EVENTTYPE" == "Test" ]]; then
    printf '%s | INFO  | Sonarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    printferr "Connection Test"
    exit 0;
else
    printf '%s | INFO  | Sonarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    printferr "Processing..."
fi

if [ -e "$STORED_FILE" ]
then
    printf '%s | INFO  | Processing new download of: %s\n' "$DT" "${sonarr_series_title}" >> "$LOG"
    printf '%s | INFO  | Torrent ID: %s | Torrent Name: %s\n' "$DT" "$TORRENT_ID" "$TORRENT_NAME" >> "$LOG"
    printf '%s | INFO  | Season folder detected as: %s\n' "$DT" "$SPATH" >> "$LOG"
    
    #get torrent folder name if it has one
    if [ "$TORRENT_DIR" != "$DLDIR" ]; then
        printferr "Torrent downloads into directory, not only file(s)"
        printf '%s | INFO  | Torrent downloads into directory, not only file(s): /%s\n' "$DT" "$TORRENT_DIR" >> "$LOG"
        printf '%s | INFO  | Torrent must be moved accordingly! Creating directory...\n' "$DT" >> "$LOG"

        if [ ! -d "$TDEST" ]; then
            mkdir "$TDEST"
            if [ $? -eq 0 ]; then
                printf '%s | INFO  | Directory created: %s\n' "$DT" "$TDEST">> "$LOG"
            else
                printf '%s | ERROR | mkdir could not complete! Check Sonarr event log for more info\n' "$DT" >> "$LOG"
            fi
        else
            printf '%s | INFO  | Directory already exists not creating again\n' "$DT" >> "$LOG"
        fi

        mv "$STORED_FILE" "$TDEST"
        if [ $? -eq 0 ]; then
            printf '%s | INFO  | Moving file from: %s  ->  %s\n' "$DT" "$STORED_FILE" "$TDEST">> "$LOG"
        else
            printf '%s | ERROR  | mv could not complete! Check Sonarr event log for more info\n' "$DT" >> "$LOG"
        fi
    fi
    
    #-t TorrentID --find NewTorrentDataLocation
    $REMOTE -t "$TORRENT_ID" --find "$DEST"
    printf '%s | INFO  | Torrent ID: %s, data now in: %s\n' "$DT" "$TORRENT_ID" "$STORED_FILE" >> "$LOG"

    if [ -e "$ORIGIN_FILE" ]
    then
        rm -f "$ORIGIN_FILE"
        printf '%s | INFO  | Deleting origin file: %s from %s\n' "$DT" "$TORRENT_NAME" "$SOURCEDIR" >> "$LOG"
        
        #If this is a season folder we'll move everything before sonarr does
        #That way we only move files once and we dont spam torrent client with updates
        
        if [ "$TORRENT_DIR" != "$DLDIR" ]; then
            rm -d "$SOURCEDIR"
            if [ $? -eq 0 ]; then
                printf '%s | INFO  | Cleaning up empty directories %s\n' "$DT" "$SOURCEDIR" >> "$LOG"
            else
                printf '%s | WARN  | Failed to remove directory, checking to see if we have to move additional files!\n' "$DT" >> "$LOG"
                COPYFILES=$(cp -r -u -v  "$SOURCEDIR"/* "$TDEST" 2>&1)
                if [ $? -eq 0 ]; then
                    printf '%s | INFO  | Moved additional files as follows:\n%s\n' "$DT" "$COPYFILES" >> "$LOG"
                    printferr "Folder detected and copied files in folder"
                    printferr "$COPYFILES"
                    
                    rm -rf "$SOURCEDIR"
                    printf '%s | INFO  | Deleted original additional files %s\n' "$DT" "$TDEST" >> "$LOG"
                    #We moved torrent folders, verify torrent to make sure everything is ok!
                    $REMOTE -t "$TORRENT_ID" -v
                else
                    printferr "| ERROR | Could not move additional files."
                    printferr "$COPYFILES"
                    printf '%s | ERROR | Could not move additional files.\n' "$DT" >> "$LOG"
                fi
            fi
            
        fi
        
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
