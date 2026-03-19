# Use an official lightweight Python base image
FROM python:3.13-slim

# Set the working directory inside the container
WORKDIR /app

# Copy and install dependencies first (Docker layer caching optimisation)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY app.py .

# Expose the port the app runs on
EXPOSE 8000

# Run the app with gunicorn (production server)
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app:app"]