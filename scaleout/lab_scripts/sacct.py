#!/bin/env python3
import time
import os
import sys
import openapi_client
from openapi_client.rest import ApiException
from pprint import pprint
# Defining the host is optional and defaults to http://localhost/slurm/v0.0.36
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://rest/",
    api_key = {
        "X-SLURM-USER-NAME": os.environ['LOGNAME'],
        "X-SLURM-USER-TOKEN": os.environ['SLURM_JWT']
    }
)
from openapi_client.models import V0036JobSubmission as jobSubmission
from openapi_client.models import V0036JobProperties as jobProperties
from openapi_client.api import SlurmApi as slurm
# Create an instance of the API class
s = slurm(openapi_client.ApiClient(configuration))
try:
        pprint(s.slurmdbd_get_job(sys.argv[1]))
except ApiException as e:
        print("Exception when calling: %s\n" % e)

