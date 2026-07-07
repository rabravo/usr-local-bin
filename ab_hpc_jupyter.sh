#!/bin/bash

# Function to display usage message
usage() {
	BASENAME=`basename $0`
	echo "Usage: $BASENAME <port>"
	echo
	echo "Arguments:"
	echo "  port          Local port to bind"
	echo
	echo "Example:"
	echo "  $BASENAME 8889"
	exit 1
}

# Check for minimum number of arguments
if [ $# -lt 1 ]; then
	usage
fi

jupyter lab  --no-browser --port=$1 --ip=0.0.0.0


