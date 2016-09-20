#!/usr/bin/env python
# -*- coding: utf-8 -*-

import click
import h5py
import numpy as np

@click.group()
def main():
    """Main command."""
    pass


def display_dataset(ax, group):
    """Display a dataset."""
    ax.set_title(group.name)
    data = group['data'][...]
    print("{:s} -> {!r}".format(group.name, data.shape))
    data = data.reshape(data.shape[0],-1)
    
    mask = group['mask'][...]
    top = np.ones_like(mask)
    bot = np.zeros_like(mask)
    t = np.arange(mask.shape[0])
    data[mask == 0,:] = np.nan
    print("{:s} -> {!r}".format(group.name, data.shape))
    print(mask)
    if data.shape[1] > 2048:
        data = np.nanmean(data, axis=1)
    ax.plot(t, data, 'k.', alpha=0.1)
    ax.fill_between(t, top, bot, where=(mask==1), color='k', alpha=0.1, transform=ax.get_xaxis_transform())
    # ax.hist(data.flatten()[np.isfinite(data.flatten())], bins=100)

@main.command()
@click.option("--filename", type=click.Path(), default="zeeko.test.hdf5")
def plot(filename):
    """Plot the test file."""
    import matplotlib.pyplot as plt
    
    with h5py.File(filename, 'r') as f:
        for g in f.values():
            fig = plt.figure()
            ax = fig.add_subplot(1,1,1)
            display_dataset(ax, g)
    plt.show()

if __name__ == '__main__':
    main()