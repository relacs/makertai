#!/bin/bash

DIR=$(dirname $0)
source "$DIR/../report_tools.sh"

{
# General information:
FILE=$(ls $DIR/latencies-* | head -n 1)
hardware_summary $FILE
kernel_parameter $FILE
performance_header $FILE

# Comparison of selected test results:
performance_data "Idle machine" idle.png  data:isolcpu $DIR/latencies-*-idle-*
performance_data "Full load" full.png data:isolcpu $DIR/latencies-*-cimn-*
} > "$DIR/report.md"
