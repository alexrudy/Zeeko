# -*- coding: utf-8 -*-

import pytest
import collections
import contextlib
import time

from ..utils.stopwatch import Stopwatch


class ZeekoTestBase(object):
    """A base class for all Zeeko tests."""
    
    @contextlib.contextmanager
    def running_loop(self, ioloop, timeout):
        """Running loop."""
        assert timeout, "Must set a timeout for the loop."
        with ioloop.running(timeout=timeout):
            ioloop.state.selected("RUN").wait(timeout=timeout)
            assert ioloop.state.selected("RUN").is_set()
            yield
        ioloop.state.selected("STOP").wait(timeout=timeout)
        assert ioloop.state.selected("STOP").is_set()
    
    def run_loop_safely(self, ioloop, callback, n, timeout=0.1):
        """Run the IOLoop safely, ensuring that things end."""
        assert timeout, "Must set a timeout for the loop."
        with self.running_loop(ioloop, timeout):
            for i in range(n):
                callback()
                time.sleep(timeout)
        
    def run_loop_counter(self, ioloop, counter_callback, callback, timelimit=None, nevents=100, timeout=0.1):
        """Run the IOLoop for a specified number of events."""
        if not timelimit:
            timelimit = (timeout * nevents * 1.1)
        sw = Stopwatch()
        sw.start()
        with self.running_loop(ioloop, timeout):
            while counter_callback() < nevents and sw.stop() < timelimit:
                callback()
        duration = sw.stop()
        return duration


class ZeekoMappingTests(ZeekoTestBase):
    """A base class for testing a mapping"""
    
    @pytest.fixture
    def mapping(self):
        """Return the mapping."""
        return {'hello':'world'}
    
    @pytest.fixture
    def keys(self):
        """Return a list of keys suitable for use with this mapping."""
        return ["hello"]
        
    @pytest.fixture
    def missing_key(self):
        """Return a key which isn't in the mapping."""
        return "missing"
        
    def assert_value_for_key(self, key, value):
        """Assert that a value is correct for a key."""
        assert value == 'world'
    
    def test_getitem(self, mapping, keys):
        """Test the mappings"""
        for key in keys:
            self.assert_value_for_key(key, mapping[key])
        
    def test_length(self, mapping, keys):
        """Test the length of the mapping."""
        assert len(mapping) == len(keys)
    
    def test_iterator(self, mapping, keys):
        """Test iterating over keys."""
        assert isinstance(mapping, collections.Iterable)
        assert isinstance(iter(mapping), collections.Iterator)
        assert set(mapping) == set(keys)
    
    def test_contains(self, mapping, keys, missing_key):
        """Test that mapping contains works"""
        for key in keys:
            assert key in mapping
        assert missing_key not in mapping
    
    def test_keys(self, mapping, keys):
        """Test keys view."""
        assert set(mapping.keys()) >= set(keys)
    
    def test_values(self, mapping, keys):
        """Test the values view."""
        values = [mapping[key] for key in keys]
        assert set(mapping.values()) >= set(values)
    
    def test_items(self, mapping, keys):
        """Test the mapping items view."""
        items = [(key, mapping[key]) for key in keys]
        assert set(mapping.items()) >= set(items)
    
    def test_get(self, mapping, keys, missing_key):
        """Test get"""
        default = object()
        for key in keys:
            value = mapping.get(key, default)
            assert value is not default
            self.assert_value_for_key(key, value)
        value = mapping.get(missing_key, default)
        assert value is default
    
    
        