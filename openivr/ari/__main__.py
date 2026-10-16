"""Entry point for python -m openivr.ari."""

import sys
from .service import run_app

if __name__ == "__main__":
    sys.exit(run_app())
