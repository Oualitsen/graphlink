import os
import sys
from pathlib import Path

sys.path.insert(0, os.getcwd())
sys.path.insert(1, str(Path(__file__).resolve().parent))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "django_site.settings")

import uvicorn
from django.core.asgi import get_asgi_application

from django_site.services import services
from generated.app import create_app

app = create_app(services, get_asgi_application())

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ["PORT"]), log_level="warning")
