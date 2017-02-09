# -*- coding: utf-8 -*-

import pytest
import time
import functools
import zmq
from ..handlers import RClient, WClient
from zeeko.conftest import assert_canrecv
from ...handlers.tests.test_base import SocketInfoTestBase

class TestRClient(SocketInfoTestBase):
    """Test the client socket."""
    
    cls = RClient
    
    @pytest.fixture
    def socketinfo(self, pull, push):
        """Socket info"""
        c = self.cls(pull, zmq.POLLIN)
        yield c
        c.close()
    
    def test_no_loop(self, socketinfo, Publisher, push):
        """Test client without using the loop."""
        time.sleep(0.01)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.recorder.receive(socketinfo.socket)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.recorder.receive(socketinfo.socket)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.recorder.receive(socketinfo.socket)
        time.sleep(0.1)
        print(socketinfo.recorder.last_message)
        assert socketinfo.recorder.counter != 0
        assert len(socketinfo.recorder) == 3
        socketinfo.close()
    
    def test_callback(self, ioloop, socketinfo, Publisher, push):
        """Test client without using the loop."""
        time.sleep(0.01)
        for n in range(3):
            Publisher.publish(push)
            assert_canrecv(socketinfo.socket)
            socketinfo(socketinfo.socket, socketinfo.socket.poll(timeout=100), ioloop._interrupt)
        print(socketinfo.recorder.last_message)
        assert socketinfo.recorder.counter != 0
        assert len(socketinfo.recorder) == 3
        socketinfo._close()
        
    def test_attached(self, ioloop, socketinfo, Publisher, push):
        """Test explicitly without the options manager."""
        socketinfo.attach(ioloop)
        
        n = 3
        self.run_loop_safely(ioloop, functools.partial(Publisher.publish, push), n)
        
        assert socketinfo.recorder.counter != 0
        assert socketinfo.recorder.counter == n * len(Publisher)
        print(socketinfo.recorder.last_message)
        assert len(socketinfo.recorder) == len(Publisher)
    
    # def test_suicidal_snail(self, ioloop, socketinfo, Publisher, push):
    #     """Test the suicidal snail pattern."""
    #
    #     socketinfo.attach(ioloop)
    #     socketinfo.snail.nlate_max = 2 * len(Publisher)
    #     socketinfo.snail.delay_max = 0.01
    #     socketinfo.use_reconnections = False
    #     Publisher.publish(push)
    #     time.sleep(0.1)
    #     ioloop.start()
    #     try:
    #         ioloop.state.selected("RUN").wait()
    #         time.sleep(0.01)
    #         ioloop.pause()
    #         ioloop.state.selected("PAUSE").wait()
    #         assert socketinfo.recorder.counter == 1 * len(Publisher)
    #         assert socketinfo.snail.nlate == len(Publisher)
    #         ioloop.pause()
    #         ioloop.state.selected("PAUSE").wait()
    #         Publisher.publish(push)
    #         time.sleep(0.01)
    #         ioloop.resume()
    #         ioloop.state.selected("RUN").wait()
    #         assert socketinfo.snail.nlate == len(Publisher)
    #         ioloop.pause()
    #         ioloop.state.selected("PAUSE").wait()
    #         Publisher.publish(push)
    #         Publisher.publish(push)
    #         Publisher.publish(push)
    #         time.sleep(0.01)
    #         ioloop.resume()
    #         ioloop.state.selected("RUN").wait()
    #         time.sleep(0.1)
    #         assert socketinfo.snail.deaths == 1
    #     finally:
    #         ioloop.stop()
    #     assert socketinfo.recorder.counter != 0
    #     print(socketinfo.recorder.last_message)
    #     assert len(socketinfo.recorder) == 3
    #
    # def test_suicidal_snail_reconnections(self, ioloop, socketinfo, Publisher, push, address):
    #     """Ensure that reconnections prevent receiving during pauses."""
    #     socketinfo.attach(ioloop)
    #     socketinfo.snail.nlate_max = 2 * len(Publisher)
    #     socketinfo.snail.delay_max = 0.01
    #     socketinfo.enable_reconnections(address)
    #     Publisher.publish(push)
    #     time.sleep(0.1)
    #     ioloop.start()
    #     try:
    #         ioloop.state.selected("RUN").wait()
    #         time.sleep(0.01)
    #         assert socketinfo.recorder.counter == 0
    #         ioloop.resume()
    #         ioloop.state.selected("RUN").wait()
    #         Publisher.publish(push)
    #         Publisher.publish(push)
    #         Publisher.publish(push)
    #         time.sleep(0.01)
    #         ioloop.resume()
    #         ioloop.state.selected("RUN").wait()
    #         time.sleep(0.1)
    #         assert socketinfo.recorder.counter == 4 * len(Publisher)
    #     finally:
    #         ioloop.stop()
    #     assert socketinfo.recorder.counter != 0
    #     print(socketinfo.recorder.last_message)
    #     assert len(socketinfo.recorder) == 3
    
    def test_pubsub(self, ioloop, address, context, Publisher, pub):
        """Test the pub/sub algorithm."""
        client = self.cls.at_address(address, context, kind=zmq.SUB)
        client.attach(ioloop)
        n = 3
        self.run_loop_safely(ioloop, functools.partial(Publisher.publish, pub), n)
        assert client.recorder.counter != 0
        print(client.recorder.last_message)
        assert len(client.recorder) == 3
