import json
import logging

from redis.asyncio import Redis

from src.config import Settings

logger = logging.getLogger(__name__)


class CacheService:
    def __init__(self, settings: Settings) -> None:
        self._ttl = settings.valkey_ttl_seconds
        self._client: Redis = Redis(
            host=settings.valkey_host,
            port=settings.valkey_port,
            decode_responses=True,
        )

    async def get(self, key: str) -> tuple[dict | None, int | None]:
        """Return (data, remaining_ttl) or (None, None) on miss."""
        value = await self._client.get(key)
        if value is None:
            return None, None

        ttl = await self._client.ttl(key)
        return json.loads(value), ttl

    async def set(self, key: str, data: dict) -> None:
        await self._client.setex(key, self._ttl, json.dumps(data))

    async def close(self) -> None:
        await self._client.aclose()

    @staticmethod
    def current_key(city: str, units: str) -> str:
        return f"weather:current:{city.lower()}:{units}"

    @staticmethod
    def forecast_key(city: str, days: int, units: str) -> str:
        return f"weather:forecast:{city.lower()}:{days}:{units}"
