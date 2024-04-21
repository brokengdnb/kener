#!/bin/sh
rsync -avrz --progress /config /configBackup

# options
#   -a  archive
#   -v  verbose
#   -r  recursive
#   -z  compress