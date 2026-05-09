from django.conf import settings
from django.urls import path

from api import views

urlpatterns = [
    path("api/health", views.health),
    path("api/dashboard", views.dashboard),
    path("api/settings", views.app_settings),
    path("api/files/upload", views.upload_file),
    path("api/files/<str:file_id>/url", views.get_file_url),
]

if settings.DEBUG:
    urlpatterns += [
        path("api/test/error", views.test_error),
        path("api/test/audit", views.test_audit),
        path("api/test/send-email", views.send_test_email),
    ]
