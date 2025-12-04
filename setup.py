from setuptools import setup
from torch.utils.cpp_extension import CppExtension, BuildExtension

setup(
    name='edge_generator',
    ext_modules=[
        CppExtension(
            'edge_generator',
            ['dataset/graph/edge_generator.cpp'],
        )
    ],
    cmdclass={
        'build_ext': BuildExtension
    }
)
