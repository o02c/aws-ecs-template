from django.urls import path

from api import views

urlpatterns = [
    path("health", views.health),
    path("api/dashboard", views.dashboard),
    path("api/settings", views.app_settings),
    path("api/files/upload", views.upload_file),
    path("api/files/<str:file_id>/url", views.get_file_url),
    # Test endpoints for verifying structured logging
    path("api/test/error", views.test_error),
    path("api/test/audit", views.test_audit),
]
