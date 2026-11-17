from generated.app import create_urlpatterns

from .services import services

urlpatterns = create_urlpatterns(services)
