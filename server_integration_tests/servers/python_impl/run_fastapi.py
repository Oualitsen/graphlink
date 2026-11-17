import os
import sys
from pathlib import Path

sys.path.insert(0, os.getcwd())
sys.path.insert(1, str(Path(__file__).resolve().parent))

import uvicorn

from generated.app import GraphLinkServices, create_app
from impl.wiring import build_services

app = create_app(build_services(GraphLinkServices, os.environ.get("GL_MODE", "mix")))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ["PORT"]), log_level="warning")
