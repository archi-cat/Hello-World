from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello World!", 200

@app.route("/health")
def health():
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)


""" **What each part does:**

- `Flask` is a lightweight Python web framework. It listens for HTTP requests and returns responses.
- The `"/"` route is your main endpoint — visiting your app's URL returns `"Hello World!"`.
- The `"/health"` route is a health check endpoint. Azure App Service uses this to verify your app is running correctly. Without it, Azure may think your app has crashed and restart it.
- `host="0.0.0.0"` means the app listens on all network interfaces inside the container — required for Docker to forward traffic to it.
- `port=8000` is the port your app runs on inside the container. """