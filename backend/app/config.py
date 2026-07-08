from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Database
    DATABASE_URL: str

    # Anthropic API
    ANTHROPIC_API_KEY: str = ""

    # VAPI Voice Calls
    VAPI_API_KEY: str = ""
    VAPI_PHONE_NUMBER_ID: str = ""
    CALLBACK_BASE_URL: str = "http://localhost:8000/api/v1"

    # Google OAuth
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""

    # Auth0
    AUTH0_DOMAIN: str = ""
    AUTH0_AUDIENCE: str = ""

    # Local development only: bypass Auth0 and use a fixed dev user.
    # MUST stay false in production.
    DEV_AUTH_BYPASS: bool = False
    DEV_USER_EMAIL: str = "dev@goalcraft.local"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"  # Ignore extra env vars


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
