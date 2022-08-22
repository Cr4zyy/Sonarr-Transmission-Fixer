#!/bin/bash
#A script to list your plex media server library and matching key number for the main script
#VARS
PLEX_TOKEN=$1

if [ -z $1 ]; then
    printf 'Please supply your plex server token.\nUsage:\n./plex_library_key.sh YOUR_PLEX_TOKEN\n'
fi

lib=$(curl -s http://127.0.0.1:32400/library/sections?X-Plex-Token=$PLEX_TOKEN | grep "<Directory")
keys=$(echo "$lib" | grep -o 'key="[^"]"*')

count=$(echo "$keys" | wc -l)
start=1

for (( c=$start; c<=$count; c++ ))
do
        title=$(echo "$lib" | grep -o 'title="[^"]*' | head -n$c | tail -1)
        key=$(echo "$lib" | grep -o 'key="[^"]"*' | head -n$c | tail -1)
        printf "%-20s %-20s\n" "$title" "$key"
done
