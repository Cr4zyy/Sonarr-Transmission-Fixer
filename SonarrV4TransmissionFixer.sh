#!/bin/bash
# For Sonarr v4+
# A simple script for Sonarr to run on download completion
# Lets Sonarr handle copying of the downloaded file and then
# updates the location of the seeded file for Transmission
# and finally removes the original downloaded file
# https://github.com/Cr4zyy/Sonarr-Transmission-Fixer

#VARIABLES set these before you start!
#transmission
REMOTE="transmission-remote 127.0.0.1:9091 -n USER:PASSWD" #Change USER and PASSWD and ip as required
ENABLE_TORRENT_VERIFY=0 # set 1 to verify torrents after folder moves, doesnt apply to a single file download
#sonarr
DLDIR="sonarr" #Name of the folder sonarr downloads all torrents into, customised with 'Category' option in download client options
ENABLE_SONARR_REFRESH=0 # set 1 if you want sonarr to refresh the series after moving a season folder download to scan all the newly moved files
APIKEY="your_sonarr_api_key" #Only needed if ENABLE_SONARR_REFRESH=1 Sonarr API Key, found in 'Settings > General'
#plex
ENABLE_PLEX_TRASH=0 # set 1 if you want the script to clear plex trash after moving files, some setups might end up with trash files and this just helps keep it tidy
PLEXTOKEN="your_plex_token" #only if ENABLE_PLEX_TRASH=1
LIBRARY="your_library_id_key" #only used if ENABLE_PLEX_TRASH=1 sectionid/key of tv library on plex (use plex_library_key.sh to find this easily)

#IPS AND PORTS change as needed
PLEX_IP="127.0.0.1"
PLEX_PORT="32400"
SONARR_IP="127.0.0.1"
SONARR_PORT="8989"

#Below here are the sonarr env variables, I use an unraid system with multiple containers and no "atomic" hard links. The comments explain my mount paths, they might not explain yours so it may need some tweaks.
#DEST is the UNRAID DRIVE DIR (where transmission puts completed downloads)
DEST="${sonarr_series_path}" # /tv/SHOW_NAME/ 
SPATH="${sonarr_episodefile_relativepath}"
TORRENT_NAME="${sonarr_episodefile_scenename}"
TORRENT_ID="${sonarr_download_id}"
#STORED_FILE is relative to SONARR container
STORED_FILE="${sonarr_episodefile_path}" # /tv/SHOW_NAME/SEASON/EPISODE.file
FILE_NAME=$(basename "$STORED_FILE")
#ORIGIN is relative to Transmission container
ORIGIN_FILE="${sonarr_episodefile_sourcepath}" # /torrents/sonarr/TORRENT.dir.file
EVENTTYPE="${sonarr_eventtype}"
SOURCEDIR="${sonarr_episodefile_sourcefolder}" # /torrents/sonarr
TITLE="${sonarr_series_title}"
SERIES_ID="${sonarr_series_id}"

SPATH=$(echo "${SPATH%/*}") # "Season xx"
DEST+="/$SPATH"

# fix paths, this allows you to the expected destination of [[SONARR CONTAINER] /tv/etc] to my transmission container which mounts the same location but at [[Transmission container] /mnt/shares/tv/etc]
# by default this will add /mnt/ to the start of your sonarr tv path, you can change this as necessary it will only ever be used to tell transmission where the moved files are located so it can update the file location for seeding.
TRANS_DEST="/mnt$DEST"

TORRENT_DIR=$(basename "$SOURCEDIR") # this should match DLDIR above which is the folder sonarr will download its torrents into. This then is used to check if the download is in a folder.
TDEST="$DEST/$TORRENT_DIR" #/tv/SHOW_NAME/SEASON/TORRENT_DIR

# logging vars
DT=$(date '+%Y-%m-%d %H:%M:%S')
LOG=$(dirname $0)
LOG+="/sonarrtransmissionfixer.log"
LOGLINES="100"
ENABLE_DEBUG=0 # set to 1 to dump variables into log and exit

printferr() { printf '%s\n' "$@" 1>&2; }

if [[ "$EVENTTYPE" == "Test" ]]; then
    printf '%s | INFO  | Sonarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    printferr "Successful connection test"
    exit 0
elif [[ "$EVENTTYPE" == "Download" ]]; then
    printf '%s | INFO  | Sonarr Event - %s | %s | %s\n' "$DT" "$EVENTTYPE" "$SPATH" "${sonarr_episodefile_episodenumbers}" >> "$LOG"
    printferr "Processing id: $SERIES_ID | $TITLE | $SPATH | Episode ${sonarr_episodefile_episodenumbers}"
else
    printf '%s | WARN  | Unsupported Sonarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    printferr "Unsupported Event Type: %EVENTTYPE, only supports Import/Upgrade downloads"
    ENABLE_DEBUG=1
fi
if [ $ENABLE_DEBUG -eq 1 ]; then
    printf '%s | DEBUG  | DEST - %s\n' "$DT" "$DEST" >> "$LOG"
    printf '%s | DEBUG  | SPATH - %s\n' "$DT" "$SPATH" >> "$LOG"
    printf '%s | DEBUG  | TORRENT_NAME - %s\n' "$DT" "$TORRENT_NAME" >> "$LOG"
    printf '%s | DEBUG  | TORRENT_ID - %s\n' "$DT" "$TORRENT_ID" >> "$LOG"
    printf '%s | DEBUG  | STORED_FILE - %s\n' "$DT" "$STORED_FILE" >> "$LOG"
    printf '%s | DEBUG  | ORIGIN_FILE - %s\n' "$DT" "$ORIGIN_FILE" >> "$LOG"
    printf '%s | DEBUG  | EVENTTYPE - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    printf '%s | DEBUG  | SOURCEDIR - %s\n' "$DT" "$SOURCEDIR" >> "$LOG"
    printf '%s | DEBUG  | TITLE - %s\n' "$DT" "$TITLE" >> "$LOG"
    printf '%s | DEBUG  | SERIES_ID - %s\n' "$DT" "$SERIES_ID" >> "$LOG"
    printf '%s | DEBUG  | TORRENT_DIR - %s\n' "$DT" "$TORRENT_DIR" >> "$LOG"
    printf '%s | DEBUG  | TDEST - %s\n' "$DT" "$TDEST" >> "$LOG"
    exit 0
fi


if [ -e "$STORED_FILE" ]
then
    printf '%s | INFO  | Processing new download of: %s\n' "$DT" "${sonarr_series_title}" >> "$LOG"
    printf '%s | INFO  | Torrent ID: %s | Torrent Name: %s\n' "$DT" "$TORRENT_ID" "$TORRENT_NAME" >> "$LOG"
    printf '%s | INFO  | Season folder detected as: %s\n' "$DT" "$SPATH" >> "$LOG"
    
    #get torrent folder name if it has one
    #this handles season packs or episodes in folders
    if [ "$TORRENT_DIR" != "$DLDIR" ]; then
        printf '%s | INFO  | Torrent downloads into a directory, not only file(s): /%s\n' "$DT" "$TORRENT_DIR" >> "$LOG"
        printf '%s | INFO  | Torrent must be moved accordingly! Creating directory...\n' "$DT" >> "$LOG"

        if [ ! -d "$TDEST" ]; then
            mkdir "$TDEST"
            if [ $? -eq 0 ]; then
                printf '%s | INFO  | Directory created: %s\n' "$DT" "$TDEST">> "$LOG"
            else
                printf '%s | ERROR | mkdir could not complete! Check Sonarr log for more info\n' "$DT" >> "$LOG"
            fi
        else
            printf '%s | INFO  | Directory already exists\n' "$DT" >> "$LOG"
        fi
        
        #move file back into origin folder name so we can still torrent
        mv "$STORED_FILE" "$TDEST"
        if [ $? -eq 0 ]; then
            printf '%s | INFO  | Moving file: %s\n' "$DT" "$FILE_NAME">> "$LOG"
            printf '%s | INFO  | From  : %s\n' "$DT" "$DEST" >> "$LOG"
            printf '%s | INFO  | To -> : %s\n' "$DT" "$TDEST">> "$LOG"
        else
            printf '%s | ERROR  | mv could not complete! Check Sonarr log for more info\n' "$DT" >> "$LOG"
        fi
        
        # sonarr v4 changed a bunch of stuff, working on 4.0.11.2793(23/dec/24)
        SOURCE_COUNT=$(find "$SOURCEDIR" -maxdepth 1 -type f | wc -l)
        TDEST_COUNT=$(find "$TDEST" -maxdepth 1 -type f | wc -l)
        #compare downloaded file count with moved count
        if [ "$SOURCE_COUNT" -eq "$TDEST_COUNT" ]; then
            printf '%s | INFO  | All files in folder copied. %s of %s \n' "$DT" "$TDEST_COUNT" "$SOURCE_COUNT" >> "$LOG"
        
            DIFF=$(comm -3 <(ls "$SOURCEDIR" | sort) <(ls "$TDEST" | sort))
            
            if [ -z "$DIFF" ]; then
                printf '%s | INFO  | Telling Transmission to change seeding file location\n' "$DT" >> "$LOG"
                #-t TorrentID --find NewTorrentDataLocation
                $REMOTE -t "$TORRENT_ID" --find "$TRANS_DEST"
                printf '%s | INFO  | Torrent ID: %s, data now in: %s\n' "$DT" "$TORRENT_ID" "$STORED_FILE" >> "$LOG"
                
                #remove original files and make sure path is good
                if [[ "$SOURCEDIR" != "/" ]] && [[ -d "$SOURCEDIR" ]]; then
                    rm -rf "$SOURCEDIR"
                    if [ $? -eq 0 ]; then
                        #deleted source files
                        printf '%s | INFO  | Deleted original files successfully %s\n' "$DT" "$SOURCEDIR" >> "$LOG"
                        #if you move whole folders you might want to verify/refresh/empty trash
                        if [ $ENABLE_TORRENT_VERIFY -eq 1 ]; then
                            $REMOTE -t "$TORRENT_ID" -v
                            printferr "| INFO  | Telling Transmission to verify files."
                            printf '%s | INFO  | Telling Transmission to verify files\n' "$DT" >> "$LOG"
                        fi
                        if [ $ENABLE_SONARR_REFRESH -eq 1 ]; then
                            #This refreshes the series within sonarr and scans for the newly moved files instead of showing them uncompleted
                            printferr "| INFO  | Telling Sonarr to rescan series $SERIES_ID files."
                            printf '%s | INFO  | Sonarr series rescan\n' "$DT" >> "$LOG"
                            #v4 at some point removed "" around series_id
                            curl -s -H "Content-Type: application/json" -H "X-Api-Key: $APIKEY" -d '{"name":"RefreshSeries","seriesId":'$SERIES_ID'}' http://$SONARR_IP:$SONARR_PORT/api/v3/command > /dev/null
                            if [ $? -ne 0 ]; then
                                printf '%s | ERROR | Failed to communicate with Sonarr API during series refresh\n' "$DT" >> "$LOG"
                                printferr "Failed to communicate with Sonarr"
                            fi
                        fi
                        if [ $ENABLE_PLEX_TRASH -eq 1 ]; then
                            printferr "| INFO  | Telling Plex to clean up trash."
                            printf '%s | INFO  | Plex trash cleanup\n' "$DT" >> "$LOG"
                            curl -s -X PUT -H "X-Plex-Token: $PLEXTOKEN" http://$PLEX_IP:$PLEX_PORT/library/sections/$LIBRARY/emptyTrash
                            if [ $? -ne 0 ]; then
                                printf '%s | ERROR | Failed to communicate with Plex during trash emptying\n' "$DT" >> "$LOG"
                                printferr "Failed to communicate with Plex"
                            fi
                        fi
                    else
                        #couldnt delete source files oops
                        printf '%s | ERROR  | Failed to remove source directory: %s\n' "$DT" "$SOURCEDIR" >> "$LOG"
                        printferr "Could not delete source directory, original files remain here: $SOURCEDIR"
                    fi
                else
                    printf '%s | ERROR | %s, is a bad SOURCEDIR variable\n' "$DT" "$SOURCEDIR">> "$LOG"
                fi
            else
                printf '%s | ERROR | Not all source files were detected as copied yet.\n' "$DT" >> "$LOG"
                printf '%s | ERROR | Original source dir exists still and Transmission still seeds from it.\n' "$DT" >> "$LOG"
                printferr "Not all source files were detected in: $TDEST"
            fi
        else
            printf '%s | WARN  | Waiting for more files to process: Currently %s of %s\n' "$DT" "$TDEST_COUNT" "$SOURCE_COUNT" >> "$LOG"
            printferr "$TITLE | $SPATH | Waiting for more files to process, currently $TDEST_COUNT of $SOURCE_COUNT"
        fi
    else
        printf '%s | INFO  | Single file detected: /%s\n' "$DT" "$ORIGIN_FILE" >> "$LOG"
        #-t TorrentID --find NewTorrentDataLocation
        $REMOTE -t "$TORRENT_ID" --find "$TRANS_DEST"
        printf '%s | INFO  | Torrent ID: %s, data now in: %s\n' "$DT" "$TORRENT_ID" "$STORED_FILE" >> "$LOG"
    fi
 else
    if [ -e "$ORIGIN_FILE" ]
    then
        printf '%s | ERROR | Stored file not located in: %s\n' "$DT" "$STORED_FILE" >> "$LOG"
        printf '%s | ERROR | Not moving torrent file for: %s\n' "$DT" "$TORRENT_NAME" >> "$LOG"
        printferr "| ERROR | Stored file could not be found for: $ORIGIN_FILE"
    else
        printf '%s | ERROR | No file exists to move or find! %s %s\n' "$DT" "$TITLE" "$SPATH">> "$LOG"
        printferr "| ERROR | Stored file could not be found for: $TITLE $SPATH"
    fi
fi   


#Log upto a maximum of LOGLINES lines
LINECOUNT=$(wc -l < $LOG)
if (( $(echo "$LINECOUNT > $LOGLINES"| bc -l) )); then
    echo "$(tail -$LOGLINES $LOG)" > "$LOG"
fi


