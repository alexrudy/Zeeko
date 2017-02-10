#!/usr/bin/env bash
SIGNAL=${1:-9}
echo $SIGNAL
ps | grep $VIRTUAL_ENV/bin/python | ghead -n -1
ps | grep $VIRTUAL_ENV/bin/python | ghead -n -1 | awk '{ print $1 }' | xargs kill -$SIGNAL
