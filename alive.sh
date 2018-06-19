#!/bin/bash

# parameter:
N=100
SLEEP=0.5

# help:
if test "x$1" = "x--help"; then
    cat <<EOF

alive.sh [N] [S]

Print a growing string on the terminal.
This way you can see whether the computer is still alive.

N: the maximum number of characters for the string (default: $N).
S: the time to sleep between the printed lines in seconds (default: $SLEEP).

EOF
    exit 0
fi

# read from command line:
if test -n "$1"; then
    N=$1
    shift
fi
if test -n "$1"; then
    SLEEP=$1
    shift
fi

while true; do
    TEXT=""
    for i in $(seq $N); do
	echo $TEXT
	TEXT="A$TEXT"
	sleep $SLEEP
    done
    for i in $(seq $N); do
	echo $TEXT
	TEXT="${TEXT%A}"
	sleep $SLEEP
    done
done

