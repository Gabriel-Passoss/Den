import contextlib
import importlib.machinery
import importlib.util
from pathlib import Path


def load(name):
    path = Path(__file__).resolve().parents[1] / name
    loader = importlib.machinery.SourceFileLoader(f"quality_{name}", str(path))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


@contextlib.contextmanager
def patched(module, **replacements):
    kept = {name: getattr(module, name) for name in replacements}
    for name, value in replacements.items():
        setattr(module, name, value)
    try:
        yield
    finally:
        for name, value in kept.items():
            setattr(module, name, value)
