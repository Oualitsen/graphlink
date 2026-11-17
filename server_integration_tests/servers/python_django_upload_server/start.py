import os
import sys
from pathlib import Path

sys.path.insert(0, os.getcwd())
sys.path.insert(1, str(Path(__file__).resolve().parent.parent / "python_impl"))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "settings")

import uvicorn
from django.core.asgi import get_asgi_application

from generated.app import create_app
from services import services

PORT = 9971

app = create_app(services, get_asgi_application())

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="warning")
