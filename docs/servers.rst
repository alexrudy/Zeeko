Servers
*******

Servers send numpy arrays over a ZeroMQ socket at a specified frequency.

To use a server, set it up with :meth:`Server.at_address`::
    
    >>> server = Server.at_adress("inproc://server")
    >>> server
    <Server >

Reference / API
===============

.. automodapi:: zeeko.handlers.server

