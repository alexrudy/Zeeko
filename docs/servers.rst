Servers
*******

Servers send numpy arrays over a ZeroMQ socket at a specified frequency.

To use a server, set it up with :meth:`Server.at_address`::
    
    >>> server = Server.at_adress("inproc://server")
    >>> server
    <Server keys=[]>
    
Then, attach numpy arrays to the server::
    
    >>> server['my_data'] = np.random.rand(20,20)
    >>> server
    <Server framecount=0 keys=['my_data']>
    
The server requires a background I/O loop to run. To create and run a simple I/O loop for just this server::
    
    >>> server.create_ioloop()
    <IOLoop n=1 INIT>
    >>> server.loop.start()
    >>> server.loop
    <IOLoop n=1 RUN>
    

You can add or alter data being served while the I/O Loop is running::
    
    >>> server['my_data'] = np.random.rand(20,20)
    

The I/O loop can be paused to temporarily halt publishing of data::
    
    >>> server.loop.pause()
    >>> server.loop
    <IOLoop n=1 PAUSE>
    >>> server.loop.resume()
    >>> server.loop
    <IOLoop n=1 RUN>
    
When you are done using the loop, you must stop the thread::
    
    >>> server.loop.stop()
    >>> server.loop
    <IOLoop n=1 STOP>
    

A stopped I/O loop cannot be re-used.


I/O loops are described in more detail in :ref:`IOLoop`.

Reference / API
===============

.. automodapi:: zeeko.handlers.server

