def get_package_data():
    return {
        _ASTROPY_PACKAGE_NAME_ + '.tests': ['coveragerc']}

def requires_2to3():
    """Skip 2to3 on package contents."""
    return False