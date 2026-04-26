from abc import ABC, abstractmethod
from src.models.weather import CurrentWeather, ForecastWeather


class WeatherProvider(ABC):
    @abstractmethod
    async def get_current(self, city: str, units: str) -> CurrentWeather: ...

    @abstractmethod
    async def get_forecast(self, city: str, days: int, units: str) -> ForecastWeather: ...

    @abstractmethod
    async def close(self) -> None: ...
