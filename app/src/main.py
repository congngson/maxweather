import logging
import sys
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from src.api import health, weather
from src.config import Settings, get_settings
from src.providers.openweathermap import OpenWeatherMapProvider
from src.services.cache import CacheService
from src.services.weather_service import WeatherService

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator:
    settings: Settings = app.state.settings

    cache = CacheService(settings)
    provider = OpenWeatherMapProvider(settings)
    app.state.weather_service = WeatherService(provider=provider, cache=cache)

    logger.info("weather-service started [env=%s]", settings.app_env)
    yield

    await provider.close()
    await cache.close()
    logger.info("weather-service stopped")


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title="MaxWeather API",
        version="1.0.0",
        docs_url="/docs" if settings.app_env != "production" else None,
        redoc_url=None,
    )
    app.state.settings = settings

    app.include_router(health.router)
    app.include_router(weather.router)

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled error on %s %s", request.method, request.url)
        return JSONResponse(status_code=500, content={"status": "error", "message": "Internal server error"})

    return app


app = create_app()
app.router.lifespan_context = lifespan  # noqa: E305
