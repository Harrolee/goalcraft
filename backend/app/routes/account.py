"""Account management — profile + account deletion.

Apple App Store Guideline 5.1.1(v) requires any app that supports account
creation to also let users initiate account deletion from within the app.
"""
from datetime import datetime

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.database import get_db
from app.models.schemas import User
from app.services.auth0 import get_current_user

router = APIRouter(prefix="/account", tags=["account"])


class AccountResponse(BaseModel):
    id: int
    email: str
    created_at: datetime

    class Config:
        from_attributes = True


class DeleteAccountResponse(BaseModel):
    deleted: bool
    message: str


@router.get("/me", response_model=AccountResponse)
async def me(current_user: User = Depends(get_current_user)) -> AccountResponse:
    """Return the authenticated user's profile."""
    return AccountResponse.model_validate(current_user)


@router.delete("", response_model=DeleteAccountResponse)
async def delete_account(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> DeleteAccountResponse:
    """Permanently delete the account and all associated data.

    Cascades remove the user's goals, metrics, metric entries, milestones,
    chat history, and check-ins (ON DELETE CASCADE).
    """
    await db.delete(current_user)
    await db.commit()
    return DeleteAccountResponse(
        deleted=True,
        message="Your account and all associated data have been permanently deleted.",
    )
