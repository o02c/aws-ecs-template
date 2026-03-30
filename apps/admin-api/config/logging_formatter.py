import json
import logging
import traceback
from datetime import datetime, timezone


class JsonFormatter(logging.Formatter):
    def format(self, record):
        log = {
            "timestamp": datetime.fromtimestamp(
                record.created, tz=timezone.utc
            ).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        if record.exc_info and record.exc_info[0] is not None:
            log["traceback"] = "".join(
                traceback.format_exception(*record.exc_info)
            ).rstrip()

        # Carry extra fields (e.g. type, user_id, action)
        for key in ("type", "user_id", "action", "resource", "detail"):
            value = getattr(record, key, None)
            if value is not None:
                log[key] = value

        return json.dumps(log, ensure_ascii=False, default=str)
