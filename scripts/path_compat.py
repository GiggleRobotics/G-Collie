"""Path containment compatible with Ubuntu 20.04's Python 3.8.

Like Path.is_relative_to, this is lexical: callers must resolve paths first
when enforcing filesystem boundaries, including symlink containment.
"""
def is_relative_to(path, root):
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False
