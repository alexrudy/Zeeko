#!/usr/bin/env python
# -*- coding: utf-8 -*-
import click
import csv
import datetime as dt
import numpy as np
import matplotlib.pyplot as plt

@click.command()
@click.argument("logfile", type=click.File('r'))
def main(logfile):
    """Parse and plot info from the logfile."""
    times = []
    rates = []
    events = []
    etimes = []
    for event, value, time in csv.reader(logfile):
        if event == 'rate':
            rates.append(float(value))
            times.append(dt.datetime.fromtimestamp(float(time)))
        else:
            events.append(event + value)
            etimes.append(dt.datetime.fromtimestamp(float(time)))
    
    plt.plot(np.array(times), np.array(rates))
    plt.ylabel("Data Transmit Rate (Mb/s)")
    plt.xlabel("Time")
    plt.show()
    
if __name__ == '__main__':
    main()