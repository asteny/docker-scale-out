#!/bin/bash

mkdir -p -m 0755 /run/slurm
chown slurmrestd:slurmrestd -R /run/slurm

#wait for primary mgt node to be done starting up
while [[ "$(scontrol --json ping | jq -r '.pings[0].pinged')" != "UP" ]]
do
	sleep 0.25
done

exit 0
