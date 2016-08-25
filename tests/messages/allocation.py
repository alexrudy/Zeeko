#!/usr/bin/env python
# -*- coding: utf-8 -*-

import zmq
from zeeko.messages.publisher import Publisher
import numpy as np

def main():
    """Zeeko Messaging Memory Test"""
    pub = Publisher()
    pub['array1'] = np.random.randn(200,200)
    
if __name__ == '__main__':
    main()
