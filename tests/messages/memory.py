#!/usr/bin/env python
# -*- coding: utf-8 -*-

import zmq
from zeeko.messages.receiver import Receiver
from zeeko.messages.publisher import Publisher
import numpy as np

@profile
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
    
    for i in xrange(1000):
        pub.publish(push)
        pub['array1'] = np.random.randn(200, 200)
        rec.receive(pull)
        print(rec['array1'].array[1,1])
    
if __name__ == '__main__':
    main()
