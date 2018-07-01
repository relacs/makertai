#!/bin/bash

function hardware_summary {
    FILE="$1"
    HOSTNAME=$(awk -F ':[ \t]*' '/Hostname/ {print $2}' $FILE)
    DATE=$(awk -F ':[ \t]*' '/Date/ {print $2}' $FILE)
    LINUX=$(awk -F ':[ \t]*' '/Description/ {print $2}' $FILE)
    CPU=$(awk -F ':[ \t]*' '/model name/ {print $2}' $FILE)
    read KERNEL RTAI PATCH < <(sed -n -e '/Version/,/^$/{/kernel/p; /rtai/p; /patch/p}' $FILE | awk -F ': ' '{print $2}' | awk '{printf( "%s ", $1 )}')
    read MBPRODUCT MBVENDOR MBVERSION < <(sed -n -e '/\*-core/,/\*-/{/product/p; /vendor/p; /version/p}' $FILE | awk -F ': ' '{printf( "%s ", $2)}')

    echo "# ${HOSTNAME}: ${RTAI} on ${KERNEL} linux kernel"
    echo
    echo "${DATE}"
    echo
    echo "## Machine"
    echo
    echo "Linux kernel version *${KERNEL}* patched with *${PATCH}* of *${RTAI}*"
    echo
    echo "*${CPU}* on a *${MBVENDOR} ${MBPRODUCT}* motherboard (version *${MBVERSION}*)"
    echo
}


function kernel_parameter {
    FILE="$1"
    echo "## Kernel parameter:"
    sed -n -e '/Kernel parameter/,/^$/{s/^  //; p}' $FILE | sed -e '1d; /BOOT/d; /^root/d; /^ro$/d; /^quiet/d; /^splash/d; /^vt.handoff/d; /panic/d;' | while read LINE; do test -n "$LINE" && echo "* $LINE"; done
    echo
}


function performance_header {
    FILE="$1"

    N=$(../makertaikernel.sh report -f dat --select kern_latencies:n -u $FILE | grep -v '^#')
    N=$(echo $N)

    echo "## Performance"
    echo
    echo "kern/latency test for ${N} seconds."
    echo "Reported is the mean, standard deviation and the maximum value of the jitter (\`lat max - lat min\`) in nanoseconds."
    echo
}


function performance_data {
    TITLE="$1"
    shift
    PLOTFILE="$1"
    shift
    SORTCOL="$1"
    shift

    SHOW_COLUMNS=(
	$SORTCOL
	kern_latencies:mean_jitter
	kern_latencies:stdev
	kern_latencies:max
    )

    echo "### $TITLE"
    echo
    ../makertaikernel.sh report -f md ${SHOW_COLUMNS[@]/#/--select } -s "$SORTCOL" -g $PLOTFILE -u -m 'none' $@ | sed -e 's/ jitter//'
    echo
    echo "![$PLOTFILE]($PLOTFILE)\\"
    echo
    echo
}


# General information:
FILE=$(ls latencies-* | head -n 1)
hardware_summary $FILE
kernel_parameter $FILE
performance_header $FILE

# Comparison of selected test results:
performance_data "Idle machine" idle.png  data:isolcpu latencies-*-idle-*
performance_data "Full load" full.png data:isolcpu latencies-*-cimn-*
