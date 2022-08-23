#!/bin/bash
#
# A simple script for Sonarr to run on download completion
# Lets Sonarr handle copying of the downloaded file and then
# updates the location of the seeded file for Transmission
# and finally removes the original downloaded file
# https://github.com/Cr4zyy/Sonarr-Transmission-Fixer

#VARIABLES set these before you start!
#transmission
REMOTE="transmission-remote -n USER:PASSWD" #Change USER and PASSWD
#sonarr
DLDIR="sonarr" #Name of the folder sonarr downloads all torrents into, can be customised with 'Category' option in download client options
ENABLE_SONARR_REFRESH=0 #set 1 if you want sonarr to refresh the series after moving a season download (not single eps) to scan all the newly moved files
APIKEY="your_api_key" #Only needed if ENABLE_SONARR_REFRESH=1 Sonarr API Key, found in 'Settings > General'
#plex
ENABLE_PLEX_TRASH=0 #set 1 if you want the script to clear plex trash after moving files, some setups might end up with trash files and this just helps keep it tidy
PLEXTOKEN="your_plex_token" #only if ENABLE_PLEX_TRASH=1
LIBRARY="your_library_id_key" #only if ENABLE_PLEX_TRASH=1 sectionid/key of tv library on plex (use second script on github to find this easily)


#Dont modify below here
DEST="${sonarr_series_path}"
SPATH="${sonarr_episodefile_relativepath}"
TORRENT_NAME="${sonarr_episodefile_scenename}"
TORRENT_ID="${sonarr_download_id}"
STORED_FILE="${sonarr_episodefile_path}"
ORIGIN_FILE="${sonarr_episodefile_sourcepath}"
EVENTTYPE="${sonarr_eventtype}"
SOURCEDIR="${sonarr_episodefile_sourcefolder}"
TITLE="${sonarr_series_title}"
SERIES_ID="${sonarr_series_id}"

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
    printferr "Successful connection test"
    exit 0;
elif [[ "$EVENTTYPE" == "Download" ]]; then
    printf '%s | INFO  | Sonarr Event - %s | %s | %s\n' "$DT" "$EVENTTYPE" "$SPATH" "${sonarr_episodefile_episodenumbers}" >> "$LOG"
    printferr "Processing id: $SERIES_ID | $TITLE | $SPATH | Episode ${sonarr_episodefile_episodenumbers}"
else
    printf '%s | WARN  | Unsupported Sonarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    printferr "Unsupported Event Type: %EVENTTYPE, only supports Import/Upgrade downloads"
    exit 0
fi

if [ -e "$STORED_FILE" ]
then
    printf '%s | INFO  | Processing new download of: %s\n' "$DT" "${sonarr_series_title}" >> "$LOG"
    printf '%s | INFO  | Torrent ID: %s | Torrent Name: %s\n' "$DT" "$TORRENT_ID" "$TORRENT_NAME" >> "$LOG"
    printf '%s | INFO  | Season folder detected as: %s\n' "$DT" "$SPATH" >> "$LOG"
    
    #get torrent folder name if it has one
    if [ "$TORRENT_DIR" != "$DLDIR" ]; then
        printferr "Download is in its own folder"
        printf '%s | INFO  | Torrent downloads into directory, not only file(s): /%s\n' "$DT" "$TORRENT_DIR" >> "$LOG"
        printf '%s | INFO  | Torrent must be moved accordingly! Creating directory...\n' "$DT" >> "$LOG"

        if [ ! -d "$TDEST" ]; then
            mkdir "$TDEST"
            if [ $? -eq 0 ]; then
                printf '%s | INFO  | Directory created: %s\n' "$DT" "$TDEST">> "$LOG"
            else
                printf '%s | ERROR | mkdir could not complete! Check Sonarr log for more info\n' "$DT" >> "$LOG"
            fi
        else
            printf '%s | INFO  | Directory already exists not creating again\n' "$DT" >> "$LOG"
        fi

        mv "$STORED_FILE" "$TDEST"
        if [ $? -eq 0 ]; then
            printf '%s | INFO  | Moving file from: %s  ->  %s\n' "$DT" "$STORED_FILE" "$TDEST">> "$LOG"
        else
            printf '%s | ERROR  | mv could not complete! Check Sonarr log for more info\n' "$DT" >> "$LOG"
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
                    printferr "| INFO | Telling Transmission to verify files."
                    
                    if [ $ENABLE_SONARR_REFRESH -eq 1 ]; then
                        #This refreshes the series within sonarr and scans for the newly moved files instead of showing them uncompleted
                        printferr "| INFO | Telling Sonarr to rescan series $SERIES_ID files."
                        printf '%s | INFO | Sonarr series rescan\n' "$DT" >> "$LOG"
                        curl -s -H "Content-Type: application/json" -H "X-Api-Key: $APIKEY" -d '{"name":"RefreshSeries","seriesId":"'$SERIES_ID'"}' http://127.0.0.1:8989/api/v3/command > /dev/null
                    fi
                    if [ $ENABLE_PLEX_TRASH -eq 1 ]; then
                        printferr "| INFO | Telling Plex to clean up trash"
                        printf '%s | INFO | Plex trash cleanup\n' "$DT" >> "$LOG"
                        curl -s -X PUT -H "X-Plex-Token: $PLEXTOKEN" http://127.0.0.1:32400/library/sections/$LIBRARY/emptyTrash
                    fi
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
