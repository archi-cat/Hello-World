FROM python:3.13-slim

RUN apt-get update && apt-get install -y \
        curl \
        gnupg \
        unixodbc-dev \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        -o /usr/share/keyrings/microsoft.asc \
    && gpg --dearmor < /usr/share/keyrings/microsoft.asc \
        > /usr/share/keyrings/microsoft-prod.gpg \
    && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list \
        -o /tmp/mssql.list \
    && sed 's|signed-by=.*|signed-by=/usr/share/keyrings/microsoft-prod.gpg|' \
        /tmp/mssql.list \
        > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/mssql.list /usr/share/keyrings/microsoft.asc

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app:app"]