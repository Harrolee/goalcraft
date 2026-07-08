from __future__ import annotations

from functools import lru_cache
from typing import Any, Dict, Optional

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import jwt
from jose.exceptions import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.database import get_db
from app.models.schemas import User


security = HTTPBearer(auto_error=False)


async def _get_or_create_dev_user(db: AsyncSession) -> User:
    """Local-development user used when DEV_AUTH_BYPASS is enabled."""
    settings = get_settings()
    email = settings.DEV_USER_EMAIL
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()
    if user:
        return user
    user = User(email=email, auth0_id="dev|local")
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@lru_cache(maxsize=1)
def _jwks_url(domain: str) -> str:
    return f"https://{domain}/.well-known/jwks.json"


async def _fetch_jwks(domain: str) -> Dict[str, Any]:
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(_jwks_url(domain))
            response.raise_for_status()
            return response.json()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to fetch Auth0 JWKS: {exc}",
        ) from exc


def _build_rsa_key(jwks: Dict[str, Any], kid: str) -> Dict[str, str]:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return {
                "kty": key.get("kty"),
                "kid": key.get("kid"),
                "use": key.get("use"),
                "n": key.get("n"),
                "e": key.get("e"),
            }
    return {}


def _extract_email(payload: Dict[str, Any]) -> Optional[str]:
    return payload.get("email") or payload.get("https://goalcraft/email")


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> User:
    settings = get_settings()

    # Local development shortcut — never enabled in production.
    if settings.DEV_AUTH_BYPASS:
        return await _get_or_create_dev_user(db)

    if not settings.AUTH0_DOMAIN:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Auth0 is not configured on the server.",
        )

    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authorization header.",
        )

    token = credentials.credentials

    try:
        unverified_header = jwt.get_unverified_header(token)
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header.",
        ) from exc

    jwks = await _fetch_jwks(settings.AUTH0_DOMAIN)
    rsa_key = _build_rsa_key(jwks, unverified_header.get("kid"))
    if not rsa_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token signature.",
        )

    try:
        decode_options = {
            "algorithms": ["RS256"],
            "issuer": f"https://{settings.AUTH0_DOMAIN}/",
        }
        # Only validate audience if it's configured
        if settings.AUTH0_AUDIENCE:
            decode_options["audience"] = settings.AUTH0_AUDIENCE
        else:
            # Skip audience validation for SPAs without API configuration
            decode_options["options"] = {"verify_aud": False}

        payload = jwt.decode(token, rsa_key, **decode_options)
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token.",
        ) from exc

    auth0_id = payload.get("sub")
    if not auth0_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing subject.",
        )

    email = _extract_email(payload) or f"{auth0_id}@auth0.local"

    result = await db.execute(select(User).where(User.auth0_id == auth0_id))
    user = result.scalar_one_or_none()

    if user:
        if not user.email and email:
            user.email = email
            await db.commit()
        return user

    if email:
        result = await db.execute(select(User).where(User.email == email))
        existing = result.scalar_one_or_none()
        if existing and not existing.auth0_id:
            existing.auth0_id = auth0_id
            await db.commit()
            await db.refresh(existing)
            return existing

    user = User(email=email, auth0_id=auth0_id)
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user
