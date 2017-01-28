import pytest

class BaseContainerTests(object):
    """Base tests for containers"""
    
    cls = None
    
    @pytest.fixture
    def obj(self):
        """Return an object."""
        return self.cls()
    
    def test_methods(self, obj):
        """Test basic methods."""
        assert isinstance(len(obj), int)
        assert len(obj)
        assert len(obj.keys()) == len(obj)
        assert "object at 0x" not in repr(obj)
    
    