#!/bin/bash
exec 1> >(logger -s -t $(basename $0)) 2>&1

exec scontrol update SuspendExcNodes+=$(hostname -s)
