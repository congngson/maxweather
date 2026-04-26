from typing import Annotated, Literal
from fastapi import APIRouter, Depends, Query, Request
from src.models.weather import APIResponse
from src.services.weather_service import WeatherService

router = APIRouter()


def get_weather_service(request: Request) -> WeatherService:
    return request.app.state.weather_service


@router.get("/weather", response_model=APIResponse, tags=["Weather"])
async def get_current_weather(
    city: Annotated[str, Query(min_length=1, max_length=100)],
    units: Annotated[Literal["metric", "imperial", "standard"], Query()] = "metric",
    service: WeatherService = Depends(get_weather_service),
) -> APIResponse:
    return await service.get_current(city=city, units=units)


@router.get("/forecast", response_model=APIResponse, tags=["Weather"])
async def get_forecast(
    city: Annotated[str, Query(min_length=1, max_length=100)],
    days: Annotated[int, Query(ge=1, le=7)] = 5,
    units: Annotated[Literal["metric", "imperial", "standard"], Query()] = "metric",
    service: WeatherService = Depends(get_weather_service),
) -> APIResponse:
    return await service.get_forecast(city=city, days=days, units=units)
