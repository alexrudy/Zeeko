#!/usr/bin/env bash
SIGNAL=${1:-9}
pgrep -if "$VIRTUAL_ENV/bin/python" "_ASTROPY_TEST_ = True"
pkill -$SIGNAL -if "$VIRTUAL_ENV/bin/python" "_ASTROPY_TEST_ = True"
