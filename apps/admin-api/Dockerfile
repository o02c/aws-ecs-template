FROM python:3.12-slim

WORKDIR /app

# RDS Global CA bundle (Aurora cert validation) — debian-slim trust store doesn't
# include AWS PCA roots, so we install the official AWS-served bundle.
ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /etc/ssl/certs/rds-global-bundle.pem
RUN chmod 644 /etc/ssl/certs/rds-global-bundle.pem

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Run as a non-root user. The root FS is read-only at runtime; the only writable
# path is /tmp (tmpfs), which also serves as HOME and gunicorn's worker tmp dir.
RUN useradd --system --uid 10001 --user-group appuser
ENV HOME=/tmp
USER 10001

EXPOSE 8080

CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8080", "--access-logfile", "/dev/null", "--error-logfile", "-", "--logger-class", "config.gunicorn_logger.JsonLogger"]
