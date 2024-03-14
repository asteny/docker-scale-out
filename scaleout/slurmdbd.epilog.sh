#!/bin/bash
#only configure once
[ -f /var/run/slurmdbd.epilog ] && exit 0

#wait for slurmdbd to start up fully

while true
do
	sacctmgr show cluster &>/dev/null
	[ $? -eq 0 ] && break
	sleep 5
done

sacctmgr -vi add cluster "${SLURM_FEDERATION_CLUSTER}"
sacctmgr -vi add account bedrock Cluster="${SLURM_FEDERATION_CLUSTER}" Description="none" Organization="none"
sacctmgr -vi add user root Account=bedrock DefaultAccount=bedrock
sacctmgr -vi add user slurm Account=bedrock DefaultAccount=bedrock

for i in arnold bambam barney betty chip edna fred gazoo wilma dino pebbles
do
	sacctmgr -vi add user $i Account=bedrock DefaultAccount=bedrock
done

#disable admins to allow their setup in class
#sacctmgr -vi add user dino Account=bedrock DefaultAccount=bedrock admin=admin
#sacctmgr -vi add user pebbles Account=bedrock DefaultAccount=bedrock admin=admin

date > /var/run/slurmdbd.epilog

exit 0
