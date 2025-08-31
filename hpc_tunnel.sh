#!/bin/bash

# Function to display usage message
usage() {
  BASENAME=`basename $0`
  echo "Usage: $BASENAME <node_name> <node_id> <ouid> <port> [remote_port]"
  echo
  echo "Arguments:"
  echo "  node_name     The name of the HPC node (e.g., compute)"
  echo "  node_id       The ID of the HPC node (e.g., 123)"
  echo "  ouid          Your Oakland University NetID"
  echo "  port          Local port to bind (used as remote_port if not specified)"
  echo "  remote_port   (Optional) Remote port to connect to"
  echo
  echo "Example:"
  echo "  $BASENAME compute    pXX bravosalgado 8889"
  echo "  $BASENAME throughput pXX bravosalgado 8889 7778"
  exit 1
}

# Check for minimum number of arguments
if [ $# -lt 4 ]; then
  usage
fi

# Assign positional arguments
NODE_NAME="$1"
NODE_ID="$2"
OUID="$3"
LOCAL_PORT="$4"
REMOTE_PORT="${5:-$LOCAL_PORT}"

# Build full node address
NODE_ADDR="hpc-${NODE_NAME}-${NODE_ID}"
SERVER_NAME="hpc-login.oakland.edu"

# Execute SSH command
ssh -Y -v -N -4 -L "${LOCAL_PORT}:${NODE_ADDR}:${REMOTE_PORT}" "${OUID}@${SERVER_NAME}"
