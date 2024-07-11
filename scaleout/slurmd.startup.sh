#!/bin/bash
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Import our environment variables from systemd
# https://unix.stackexchange.com/questions/146995/inherit-environment-variables-in-systemd-docker-container
for e in $(tr "\000" "\n" < /proc/1/environ); do
        eval "export $e"
done

exit 0
