import os
import sys

if os.environ.get("REST_VARIANT") == "comma":
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "comma"))
