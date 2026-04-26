from collections import defaultdict
from datetime import datetime

import httpx

from src.config import Settings
from src.models.weather import CurrentWeather, DailyForecast, ForecastWeather
from src.providers.base import WeatherProvider


class OpenWeatherMapProvider(WeatherProvider):
    def __init__(self, settings: Settings) -> None:
        self._api_key = settings.openweathermap_api_key
        self._base_url = settings.openweathermap_base_url
        self._client = httpx.AsyncClient(timeout=10.0)

    async def get_current(self, city: str, units: str) -> CurrentWeather:
        response = await self._client.get(
            f"{self._base_url}/weather",
            params={"q": city, "units": units, "appid": self._api_key},
        )
        response.raise_for_status()
        data = response.json()

        return CurrentWeather(
            city=data["name"],
            country=data["sys"]["country"],
            temperature=data["main"]["temp"],
            feels_like=data["main"]["feels_like"],
            humidity=data["main"]["humidity"],
            description=data["weather"][0]["description"],
            wind_speed=data["wind"]["speed"],
            units=units,
        )

    async def get_forecast(self, city: str, days: int, units: str) -> ForecastWeather:
        response = await self._client.get(
            f"{self._base_url}/forecast",
            params={"q": city, "units": units, "appid": self._api_key, "cnt": days * 8},
        )
        response.raise_for_status()
        data = response.json()

        daily: dict[str, dict] = defaultdict(lambda: {
            "temps": [], "humidity": [], "wind": [], "descriptions": []
        })

        for item in data["list"]:
            date = datetime.fromtimestamp(item["dt"]).strftime("%Y-%m-%d")
            daily[date]["temps"].append(item["main"]["temp"])
            daily[date]["humidity"].append(item["main"]["humidity"])
            daily[date]["wind"].append(item["wind"]["speed"])
            daily[date]["descriptions"].append(item["weather"][0]["description"])

        forecasts = [
            DailyForecast(
                date=date,
                temperature_min=min(values["temps"]),
                temperature_max=max(values["temps"]),
                description=values["descriptions"][0],
                humidity=int(sum(values["humidity"]) / len(values["humidity"])),
                wind_speed=round(sum(values["wind"]) / len(values["wind"]), 1),
            )
            for date, values in sorted(daily.items())
        ][:days]

        return ForecastWeather(
            city=data["city"]["name"],
            country=data["city"]["country"],
            units=units,
            days=forecasts,
        )

    async def close(self) -> None:
        await self._client.aclose()
