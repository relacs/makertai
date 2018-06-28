#!/bin/bash

SHOW_COLUMNS=(
data:isolcpu
data:load
kern_latencies:mean_jitter
kern_latencies:stdev
kern_latencies:max
)

../makertaikernel.sh report -f md ${SHOW_COLUMNS[@]/#/--select } -s ^load -s isolcpu
