#!/usr/bin/env bash
SIGNAL=${1:-9}
ps | grep $VIRTUAL_ENV/bin/python | grep "_ASTROPY_TEST_ = True" | awk '{ print $1 $2 }'
ps | grep $VIRTUAL_ENV/bin/python | grep "_ASTROPY_TEST_ = True" | awk '{ print $1 }' | xargs kill -$SIGNAL
