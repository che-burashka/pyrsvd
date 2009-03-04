
from distutils.core import setup
from distutils.extension import Extension
setup(
    name = "rsvd",
    ext_modules = [Extension("rsvd/rsvd", ["rsvd/rsvd.c"])],
    version = "0.1",
    description="A regularized SVD solver for partial matrices",
    author='Peter Prettenhofer',
    author_email='peter.prettenhofer@gmail.com',
    url="http://code.google.com/p/pyrsvd/",
    packages=['rsvd'],

)