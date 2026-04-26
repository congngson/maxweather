from datetime import datetime
from typing import Any
from pydantic import BaseModel, Field


class CurrentWeather(BaseModel):
    city: str
    country: str
    temperature: float
    feels_like: float
    humidity: int
    description: str
    wind_speed: float
    units: str


class DailyForecast(BaseModel):
    date: str
    temperature_min: float
    temperature_max: float
    description: str
    humidity: int
    wind_speed: float


class ForecastWeather(BaseModel):
    city: str
    country: str
    units: str
    days: list[DailyForecast]


class APIResponse(BaseModel):
    status: str = "success"
    cached: bool = False
    cache_ttl_seconds: int | None = None
    source: str = "OpenWeatherMap"
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    data: Any
