#!/bin/bash

mkdir -p -m 0755 /run/slurm
chown slurmrestd:slurmrestd -R /run/slurm

#wait for primary mgt node to be done starting up
while [[ ! -s /auth/slurm ]]
do
	sleep 0.25
done

exit 0
