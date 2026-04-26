import logging

from src.models.weather import APIResponse, CurrentWeather, ForecastWeather
from src.providers.base import WeatherProvider
from src.services.cache import CacheService

logger = logging.getLogger(__name__)


class WeatherService:
    def __init__(self, provider: WeatherProvider, cache: CacheService) -> None:
        self._provider = provider
        self._cache = cache

    async def get_current(self, city: str, units: str) -> APIResponse:
        key = CacheService.current_key(city, units)
        cached_data, ttl = await self._cache.get(key)

        if cached_data is not None:
            logger.info("Cache HIT: %s", key)
            return APIResponse(
                cached=True,
                cache_ttl_seconds=ttl,
                data=CurrentWeather(**cached_data),
            )

        logger.info("Cache MISS: %s — fetching from provider", key)
        weather = await self._provider.get_current(city=city, units=units)
        await self._cache.set(key, weather.model_dump())

        return APIResponse(cached=False, data=weather)

    async def get_forecast(self, city: str, days: int, units: str) -> APIResponse:
        key = CacheService.forecast_key(city, days, units)
        cached_data, ttl = await self._cache.get(key)

        if cached_data is not None:
            logger.info("Cache HIT: %s", key)
            return APIResponse(
                cached=True,
                cache_ttl_seconds=ttl,
                data=ForecastWeather(**cached_data),
            )

        logger.info("Cache MISS: %s — fetching from provider", key)
        forecast = await self._provider.get_forecast(city=city, days=days, units=units)
        await self._cache.set(key, forecast.model_dump())

        return APIResponse(cached=False, data=forecast)
