import pytest
from unittest.mock import AsyncMock, MagicMock
from httpx import AsyncClient, ASGITransport

from src.main import create_app
from src.models.weather import APIResponse, CurrentWeather, DailyForecast, ForecastWeather


def make_current_response() -> APIResponse:
    return APIResponse(
        cached=False,
        data=CurrentWeather(
            city="Hanoi", country="VN", temperature=30.0, feels_like=33.0,
            humidity=80, description="cloudy", wind_speed=3.5, units="metric"
        ),
    )


def make_forecast_response() -> APIResponse:
    return APIResponse(
        cached=False,
        data=ForecastWeather(
            city="Hanoi", country="VN", units="metric",
            days=[
                DailyForecast(
                    date="2026-04-24", temperature_min=25.0, temperature_max=33.0,
                    description="sunny", humidity=70, wind_speed=2.0
                )
            ],
        ),
    )


@pytest.fixture
def mock_weather_service():
    service = MagicMock()
    service.get_current = AsyncMock(return_value=make_current_response())
    service.get_forecast = AsyncMock(return_value=make_forecast_response())
    return service


@pytest.fixture
def app(mock_weather_service):
    application = create_app()
    application.state.weather_service = mock_weather_service
    return application


@pytest.mark.asyncio
async def test_health_returns_200(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


@pytest.mark.asyncio
async def test_get_current_weather(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/weather?city=Hanoi&units=metric")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert body["data"]["city"] == "Hanoi"


@pytest.mark.asyncio
async def test_get_weather_missing_city(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/weather")
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_get_forecast(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/forecast?city=Hanoi&days=5")
    assert response.status_code == 200
    body = response.json()
    assert body["data"]["city"] == "Hanoi"


@pytest.mark.asyncio
async def test_get_forecast_days_out_of_range(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/forecast?city=Hanoi&days=10")
    assert response.status_code == 422
