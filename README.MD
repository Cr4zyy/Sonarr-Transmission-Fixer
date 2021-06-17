Sonarr Transmission Fixer
======
**Sonarr Transmission Fixer** allows you to update the seeded data location automatically of a torrent in Transmission, downloaded via Sonarr.

## Setup

* Change the USER:PASSWD to your USERNAME and PASSWORD for your Transmission. If you don't have a password you can remove the '-n USER:PASSWD'
* Run this script as a "custom script" from Sonarr's "Settings > Connect > Connections" option. Set it to function 'On Download' put in the path to the script and save.
* Make sure the script is executable by the Sonarr user
* Ideally meant to run with Sonarr copying files, not hardlinking
* While Sonarr can handle removing of completed downloads, the script does it itself.
* BASH script
* Can handle season packs within folders properly as of jun/2021

Sonarr will provide all the required directory and file details to the script, which will then set the seeding location of a torrent to where you store the data and remove the origin file from the default Transmission downlaod directory, Saving you from having two files.

The script will create a log file in the directory of the script, which will be a max of 100 lines at anytime.

Sonarr team aren't looking to implement this option any time soon so this is my quick fix to the issue https://github.com/Sonarr/Sonarr/issues/738

Also a script for Radarr available here https://github.com/Cr4zyy/Radarr-Transmission-Fixer
