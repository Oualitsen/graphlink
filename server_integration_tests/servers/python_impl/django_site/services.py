import os

from generated.app import GraphLinkServices
from impl.wiring import build_services

services = build_services(GraphLinkServices, os.environ.get("GL_MODE", "mix"))
