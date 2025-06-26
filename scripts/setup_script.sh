#!/bin/bash

# Usage: ./setup_script.sh

# This is needed for the kind nodes to have the files to be used as hostpath volumes in stage 1 manifests
docker cp code/timeline/init-mongo.js apollo-worker2:/etc/init-mongo.js
docker cp code/timeline/init-mongo.js apollo-worker:/etc/init-mongo.js
