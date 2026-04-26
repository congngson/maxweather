from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()


class HealthResponse(BaseModel):
    status: str
    environment: str


@router.get("/health", response_model=HealthResponse, tags=["Health"])
async def health(app_env: str = "unknown") -> HealthResponse:
    return HealthResponse(status="ok", environment=app_env)
