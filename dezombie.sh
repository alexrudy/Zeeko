#!/usr/bin/env bash
ps | grep $VIRTUAL_ENV/bin/python | ghead -n -1
ps | grep $VIRTUAL_ENV/bin/python | ghead -n -1 | awk '{ print $1 }' | xargs kill -9
