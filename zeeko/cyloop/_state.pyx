
STATE = {
    b'RUN': 1,
    b'PAUSE': 2,
    b'STOP': 3,
    b'INIT': 4,
}

class StateError(Exception):
    """An error raised due to a state problem"""