"""
OAuth routes for Google Calendar authorization.
"""

import base64
import json
import secrets
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse
from typing import Optional

from fastapi import APIRouter, HTTPException, Depends, Query, Request
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.database import get_db
from app.models.schemas import User
from app.services.calendar_service import CalendarService
from app.services.auth0 import get_current_user


router = APIRouter(prefix="/auth", tags=["auth"])


def _encode_state(payload: dict) -> str:
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("utf-8").rstrip("=")


def _decode_state(state: str) -> dict:
    padded = state + "=" * (-len(state) % 4)
    raw = base64.urlsafe_b64decode(padded.encode("utf-8"))
    return json.loads(raw.decode("utf-8"))


def _append_query(url: str, params: dict) -> str:
    parsed = urlparse(url)
    query = dict(parse_qsl(parsed.query))
    query.update({k: v for k, v in params.items() if v is not None})
    return urlunparse(parsed._replace(query=urlencode(query)))


@router.get("/me")
async def get_me(
    current_user: User = Depends(get_current_user),
) -> dict:
    return {
        "id": current_user.id,
        "email": current_user.email,
        "phone_number": current_user.phone_number,
    }


@router.get("/google/authorize")
async def google_authorize(
    request: Request,
    user_id: int = Query(..., description="User ID to authorize"),
    return_url: str = Query(..., description="Frontend URL to return to after authorization"),
) -> dict:
    """
    Get the Google OAuth authorization URL.

    Args:
        user_id: The user ID to associate with the authorization
        return_url: Frontend URL to return to after authorization

    Returns:
        Authorization URL to redirect the user to
    """
    calendar_service = CalendarService()
    redirect_uri = str(request.url_for("google_callback"))
    flow = calendar_service.get_oauth_flow(redirect_uri)

    state_payload = {
        "nonce": secrets.token_urlsafe(16),
        "user_id": user_id,
        "return_url": return_url,
    }
    encoded_state = _encode_state(state_payload)

    authorization_url, state = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent",  # Force consent to get refresh token
        state=encoded_state,
    )

    return {
        "authorization_url": authorization_url,
        "state": state,
        "user_id": user_id
    }


@router.get("/google/callback")
async def google_callback(
    request: Request,
    code: str = Query(..., description="Authorization code from Google"),
    state: str = Query(..., description="State parameter for verification"),
    user_id: Optional[int] = Query(None, description="User ID to save the token for"),
    redirect_uri: Optional[str] = Query(None, description="The same redirect URI used in authorize"),
    db: AsyncSession = Depends(get_db)
) -> RedirectResponse:
    """
    Handle the Google OAuth callback and store the refresh token.
    Also creates the dedicated GoalCraft calendar.

    Args:
        code: Authorization code from Google
        state: State parameter for CSRF protection
        user_id: User ID to save the token for
        redirect_uri: Same redirect URI used in initial authorization
        db: Database session

    Returns:
        Redirect back to the frontend with status
    """
    calendar_service = CalendarService()
    return_url = None

    if user_id is None or redirect_uri is None:
        try:
            state_payload = _decode_state(state)
            user_id = int(state_payload["user_id"])
            return_url = state_payload.get("return_url")
            if not return_url:
                raise ValueError("Missing return_url")
        except Exception as error:
            raise HTTPException(status_code=400, detail=f"Invalid state: {error}")

    redirect_uri = redirect_uri or str(request.url_for("google_callback"))
    flow = calendar_service.get_oauth_flow(redirect_uri)

    try:
        flow.fetch_token(code=code)
        credentials = flow.credentials

        if not credentials.refresh_token:
            raise HTTPException(
                status_code=400,
                detail="No refresh token received. Please revoke access and try again."
            )

        # Get user and update refresh token
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()

        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        user.google_refresh_token = credentials.refresh_token

        # Create or get the dedicated GoalCraft calendar
        try:
            calendar_info = await calendar_service.get_or_create_goalcraft_calendar(
                credentials.refresh_token,
                user.google_calendar_id
            )
            user.google_calendar_id = calendar_info.id
        except Exception as cal_error:
            print(f"Error creating GoalCraft calendar: {cal_error}")
            # Continue anyway - we'll try to create it later

        await db.commit()

        if return_url:
            target = _append_query(return_url, {"google": "connected"})
            return RedirectResponse(url=target)

        return RedirectResponse(url="/")

    except Exception as e:
        if return_url:
            target = _append_query(return_url, {"google": "error", "message": str(e)})
            return RedirectResponse(url=target)

        raise HTTPException(status_code=400, detail=f"Failed to complete OAuth: {str(e)}")


@router.get("/google/status/{user_id}")
async def google_status(
    user_id: int,
    db: AsyncSession = Depends(get_db)
) -> dict:
    """
    Check if a user has connected their Google Calendar.

    Args:
        user_id: User ID to check
        db: Database session

    Returns:
        Connection status
    """
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "connected": bool(user.google_refresh_token),
        "user_id": user_id,
        "calendar_id": user.google_calendar_id
    }


@router.delete("/google/disconnect/{user_id}")
async def google_disconnect(
    user_id: int,
    db: AsyncSession = Depends(get_db)
) -> dict:
    """
    Disconnect Google Calendar from user account.
    Note: This doesn't delete the GoalCraft calendar, just removes the connection.

    Args:
        user_id: User ID to disconnect
        db: Database session

    Returns:
        Success status
    """
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.google_refresh_token = None
    # Keep calendar_id so we can reconnect to the same calendar later
    await db.commit()

    return {
        "success": True,
        "message": "Google Calendar disconnected",
        "user_id": user_id
    }
