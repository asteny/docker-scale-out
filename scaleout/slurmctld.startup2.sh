#!/bin/bash
#wait for primary mgt node to be done starting up
while [[ "$(scontrol --json ping | jq -r '.pings[0].pinged')" != "UP" ]]
do
	sleep 0.25
done

scontrol token username=slurm lifespan=infinity | sed 's#SLURM_JWT=##g' > /auth/slurm
chmod 0755 -R /auth

sed -e '/^hosts:/d' -i /etc/nsswitch.conf
echo 'hosts:      files dns myhostname' >> /etc/nsswitch.conf

exit 0
