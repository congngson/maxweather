import json
import os
import urllib.request
import urllib.parse
import urllib.error


def handler(event, context):
    path = event.get("path", "/")

    if path == "/health":
        return _response(200, {"status": "healthy"})

    params = event.get("queryStringParameters") or {}
    city = params.get("city", "Singapore")
    units = params.get("units", "metric")
    api_key = os.environ["OWM_API_KEY"]

    if path == "/forecast":
        days = min(int(params.get("days", 5)), 7)
        url = (
            "https://api.openweathermap.org/data/2.5/forecast"
            f"?q={urllib.parse.quote(city)}&units={units}&cnt={days * 8}&appid={api_key}"
        )
    else:
        url = (
            "https://api.openweathermap.org/data/2.5/weather"
            f"?q={urllib.parse.quote(city)}&units={units}&appid={api_key}"
        )

    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
        return _response(200, {"status": "success", "cached": False, "source": "OpenWeatherMap", "data": data})
    except urllib.error.HTTPError as e:
        return _response(e.code, {"error": e.reason})
    except Exception as e:
        return _response(500, {"error": str(e)})


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
