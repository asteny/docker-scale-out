#!/bin/bash
#only configure once
[ -f /var/run/slurmctld.startup ] && exit 0

HOST="$(cat /etc/hostname)"

sed -e '/^hosts:/d' -i /etc/nsswitch.conf
echo 'hosts: files myhostname' >> /etc/nsswitch.conf

[ "${HOST}" = "mgmtnode" ] && IS_MGT=1 || IS_MGT=
[ "${HOST}" = "${SLURM_FEDERATION_CLUSTER}-mgmtnode" ] && IS_FMGT=1 || IS_FMGT=
echo "Running on host:${HOST} cluster:${SLURM_FEDERATION_CLUSTER} mgt=${IS_MGT} federated=${IS_FMGT}"

if [ "${IS_MGT}${IS_FMGT}" != "" ]
then
	if [ "$IS_FMGT" != "" ]
	then
		#force the cluster name to be the assigned
		sed -e '/^ClusterName=/d' -i /etc/slurm/slurm.conf
		echo "ClusterName=${SLURM_FEDERATION_CLUSTER}" >> /etc/slurm/slurm.conf

		sed -e '/^SlurmCtldHost=/d' -i /etc/slurm/slurm.conf
		echo "SlurmCtldHost=${SLURM_FEDERATION_CLUSTER}-mgmtnode" >> /etc/slurm/slurm.conf
		echo "SlurmCtldHost=${SLURM_FEDERATION_CLUSTER}-mgmtnode2" >> /etc/slurm/slurm.conf

	fi

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
else
	#wait for primary mgt node to be done starting up
	while [[ "$(scontrol --json ping | jq -r '.pings[0].pinged')" != "UP" ]]
	do
		sleep 0.25
	done
fi

date > /var/run/slurmctld.startup

exit 0
