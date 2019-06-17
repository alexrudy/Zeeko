Clients
*******


Clients connect to a server and receive messages streamed from that server. Commonly, they use the ZeroMQ PUB/SUB pattern, acting as a subscribing socket. Data streamed to clients is then exposed in a dictionary interface, which includes the raw numpy arrays streamed to the client.

To use a client, you can either directly call the receiving methods, or you can run the receiving in the background using an IOLoop::

    >>> from zeeko.handlers.client import Client
    >>> client = Client.at_address("inproc://testing")
    >>> client
    <Client address='inproc://testing'>
    >>> client.create_ioloop()
    <IOLoop n=1 INIT>
    >>> client.loop.start()
    >>> client
    <Client address='inproc://testing' RUN>
    >>> client.loop.pause()
    >>> client
    <Client address='inproc://testing' PAUSE>
    >>> client.loop.stop(timeout=0.1)
    >>> client
    <Client address='inproc://testing' STOP>
    

Reference / API
===============

.. automodapi:: zeeko.handlers.client

.. automodapi:: zeeko.handlers.snail

