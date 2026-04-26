from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # Application
    app_env: str = Field(..., description="Environment: staging | production")
    app_port: int = Field(default=8000)
    log_level: str = Field(default="INFO")

    # Weather provider
    weather_provider: str = Field(default="openweathermap")
    openweathermap_api_key: str = Field(..., description="OpenWeatherMap API key")
    openweathermap_base_url: str = Field(
        default="https://api.openweathermap.org/data/2.5"
    )

    # Valkey / Redis
    valkey_host: str = Field(..., description="Valkey host endpoint")
    valkey_port: int = Field(default=6379)
    valkey_ttl_seconds: int = Field(default=600)

    # Aurora PostgreSQL
    db_host: str = Field(..., description="Aurora writer endpoint")
    db_port: int = Field(default=5432)
    db_name: str = Field(..., description="Database name")
    db_user: str = Field(..., description="Database user")
    db_password: str = Field(..., description="Database password")


def get_settings() -> Settings:
    return Settings()
