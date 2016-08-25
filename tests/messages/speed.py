#!/usr/bin/env python
# -*- coding: utf-8 -*-

import zmq
from zmq.backend.cython.utils import Stopwatch
from zeeko.messages.receiver import Receiver
from zeeko.messages.publisher import Publisher
import numpy as np

def main():
    """Zeeko Messaging Memory Test"""
    ctx = zmq.Context()
    pull = ctx.socket(zmq.PULL)
    pull.bind("inproc://memtest")
    
    push = ctx.socket(zmq.PUSH)
    push.connect("inproc://memtest")
    
    pub = Publisher()
    pub['array1'] = np.random.randn(200,200)
    rec = Receiver()
    n = 1000
    w = Stopwatch()
    w.start()
    total = 0.0
    for i in range(n):
        pub.publish(push)
        pub['array1'] = np.random.randn(200, 200)
        rec.receive(pull)
        total += rec['array1'].array[1,1]
    t = w.stop()
    
    w.start()
    total = 0.0
    for i in range(n):
        total += np.random.randn(200, 200)[1,1]
    to = w.stop()
    print("Send-Recv Loop Speed: {:.4f}Hz".format(n/float(t-to)))
    
if __name__ == '__main__':
    main()
