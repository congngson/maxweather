import pytest
from unittest.mock import AsyncMock, MagicMock

from src.models.weather import CurrentWeather, ForecastWeather, DailyForecast
from src.services.weather_service import WeatherService


def make_current_weather(**kwargs) -> CurrentWeather:
    defaults = dict(
        city="Hanoi", country="VN", temperature=30.0, feels_like=33.0,
        humidity=80, description="cloudy", wind_speed=3.5, units="metric"
    )
    return CurrentWeather(**{**defaults, **kwargs})


def make_forecast_weather(**kwargs) -> ForecastWeather:
    day = DailyForecast(
        date="2026-04-24", temperature_min=25.0, temperature_max=33.0,
        description="sunny", humidity=70, wind_speed=2.0
    )
    defaults = dict(city="Hanoi", country="VN", units="metric", days=[day])
    return ForecastWeather(**{**defaults, **kwargs})


@pytest.fixture
def mock_provider():
    provider = MagicMock()
    provider.get_current = AsyncMock(return_value=make_current_weather())
    provider.get_forecast = AsyncMock(return_value=make_forecast_weather())
    return provider


@pytest.fixture
def mock_cache():
    cache = MagicMock()
    cache.get = AsyncMock(return_value=(None, None))
    cache.set = AsyncMock()
    return cache


@pytest.fixture
def service(mock_provider, mock_cache):
    return WeatherService(provider=mock_provider, cache=mock_cache)


class TestGetCurrent:
    @pytest.mark.asyncio
    async def test_cache_miss_calls_provider(self, service, mock_provider, mock_cache):
        response = await service.get_current(city="Hanoi", units="metric")

        mock_provider.get_current.assert_called_once_with(city="Hanoi", units="metric")
        mock_cache.set.assert_called_once()
        assert response.cached is False
        assert response.data.city == "Hanoi"

    @pytest.mark.asyncio
    async def test_cache_hit_skips_provider(self, service, mock_provider, mock_cache):
        weather = make_current_weather()
        mock_cache.get = AsyncMock(return_value=(weather.model_dump(), 300))

        response = await service.get_current(city="Hanoi", units="metric")

        mock_provider.get_current.assert_not_called()
        mock_cache.set.assert_not_called()
        assert response.cached is True
        assert response.cache_ttl_seconds == 300

    @pytest.mark.asyncio
    async def test_cache_miss_writes_to_cache(self, service, mock_cache):
        await service.get_current(city="Hanoi", units="metric")
        mock_cache.set.assert_called_once()


class TestGetForecast:
    @pytest.mark.asyncio
    async def test_cache_miss_calls_provider(self, service, mock_provider, mock_cache):
        response = await service.get_forecast(city="Hanoi", days=5, units="metric")

        mock_provider.get_forecast.assert_called_once_with(city="Hanoi", days=5, units="metric")
        assert response.cached is False

    @pytest.mark.asyncio
    async def test_cache_hit_skips_provider(self, service, mock_provider, mock_cache):
        forecast = make_forecast_weather()
        mock_cache.get = AsyncMock(return_value=(forecast.model_dump(), 200))

        response = await service.get_forecast(city="Hanoi", days=5, units="metric")

        mock_provider.get_forecast.assert_not_called()
        assert response.cached is True


class TestCacheKeys:
    def test_current_key_is_lowercase(self):
        from src.services.cache import CacheService
        key = CacheService.current_key("HANOI", "metric")
        assert "hanoi" in key

    def test_forecast_key_includes_days(self):
        from src.services.cache import CacheService
        key = CacheService.forecast_key("Hanoi", 5, "metric")
        assert "5" in key
