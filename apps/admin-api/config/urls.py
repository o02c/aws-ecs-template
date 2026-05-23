from django.conf import settings
from django.urls import path

from api import views

urlpatterns = [
    path("admin/api/health", views.health),
    path("admin/api/dashboard", views.dashboard),
    path("admin/api/settings", views.app_settings),
    path("admin/api/files/upload", views.upload_file),
    path("admin/api/files/<str:file_id>/url", views.get_file_url),
]

if settings.DEBUG:
    urlpatterns += [
        path("admin/api/test/error", views.test_error),
        path("admin/api/test/audit", views.test_audit),
        path("admin/api/test/send-email", views.send_test_email),
        path("admin/api/test/app-resources", views.test_app_resources),
        path("admin/api/test/db", views.test_db),
    ]
