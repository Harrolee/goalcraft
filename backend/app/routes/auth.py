"""
OAuth routes for Google Calendar authorization.
"""

from fastapi import APIRouter, HTTPException, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.database import get_db
from app.models.schemas import User
from app.services.calendar_service import CalendarService


router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/google/authorize")
async def google_authorize(
    user_id: int = Query(..., description="User ID to authorize"),
    redirect_uri: str = Query(..., description="Redirect URI after authorization")
) -> dict:
    """
    Get the Google OAuth authorization URL.

    Args:
        user_id: The user ID to associate with the authorization
        redirect_uri: Where to redirect after authorization

    Returns:
        Authorization URL to redirect the user to
    """
    calendar_service = CalendarService()
    flow = calendar_service.get_oauth_flow(redirect_uri)

    authorization_url, state = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent"  # Force consent to get refresh token
    )

    return {
        "authorization_url": authorization_url,
        "state": state,
        "user_id": user_id
    }


@router.get("/google/callback")
async def google_callback(
    code: str = Query(..., description="Authorization code from Google"),
    state: str = Query(..., description="State parameter for verification"),
    user_id: int = Query(..., description="User ID to save the token for"),
    redirect_uri: str = Query(..., description="The same redirect URI used in authorize"),
    db: AsyncSession = Depends(get_db)
) -> dict:
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
        Success status
    """
    calendar_service = CalendarService()
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

        return {
            "success": True,
            "message": "Google Calendar connected successfully",
            "user_id": user_id,
            "calendar_id": user.google_calendar_id
        }

    except Exception as e:
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
