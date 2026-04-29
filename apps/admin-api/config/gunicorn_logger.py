from gunicorn.glogging import Logger

from .logging_formatter import JsonFormatter


class JsonLogger(Logger):
    """Emit gunicorn's own log records (startup, worker boot, signals, errors)
    through the same JsonFormatter the Django app uses, so every line in the
    container's stderr is a single JSON object."""

    def setup(self, cfg):
        super().setup(cfg)
        formatter = JsonFormatter()
        for handler in self.error_log.handlers + self.access_log.handlers:
            handler.setFormatter(formatter)
