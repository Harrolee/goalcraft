from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.database import get_db
from app.models.schemas import Milestone, Goal, MilestoneStatus, User
from app.services.auth0 import get_current_user
from app.services.checkin_scheduler import schedule_checkin_for_milestone


router = APIRouter(tags=["milestones"])


# Pydantic models for request/response
class MilestoneResponse(BaseModel):
    """Response model for a milestone."""
    id: int
    goal_id: int
    title: str
    description: Optional[str] = None
    due_date: Optional[datetime] = None
    status: str
    order: int
    created_at: datetime

    class Config:
        from_attributes = True


class MilestoneUpdate(BaseModel):
    """Request model for updating a milestone."""
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    due_date: Optional[datetime] = None
    status: Optional[MilestoneStatus] = None
    order: Optional[int] = None


@router.get("/goals/{goal_id}/milestones", response_model=List[MilestoneResponse])
async def list_milestones(
    goal_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[MilestoneResponse]:
    """
    List all milestones for a specific goal.
    """
    # Check if goal exists
    goal_result = await db.execute(
        select(Goal).where(Goal.id == goal_id, Goal.user_id == current_user.id)
    )
    goal = goal_result.scalar_one_or_none()

    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Goal with id {goal_id} not found"
        )

    # Get milestones
    result = await db.execute(
        select(Milestone)
        .where(Milestone.goal_id == goal_id)
        .order_by(Milestone.order)
    )
    milestones = result.scalars().all()

    return [
        MilestoneResponse(
            id=m.id,
            goal_id=m.goal_id,
            title=m.title,
            description=m.description,
            due_date=m.due_date,
            status=m.status.value,
            order=m.order,
            created_at=m.created_at
        )
        for m in milestones
    ]


@router.patch("/milestones/{milestone_id}", response_model=MilestoneResponse)
async def update_milestone(
    milestone_id: int,
    updates: MilestoneUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> MilestoneResponse:
    """
    Update a milestone's status or other fields.
    """
    result = await db.execute(
        select(Milestone)
        .join(Milestone.goal)
        .where(Milestone.id == milestone_id, Goal.user_id == current_user.id)
    )
    milestone = result.scalar_one_or_none()

    if not milestone:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Milestone with id {milestone_id} not found"
        )

    # Apply updates
    if updates.title is not None:
        milestone.title = updates.title
    if updates.description is not None:
        milestone.description = updates.description
    if updates.due_date is not None:
        milestone.due_date = updates.due_date
    if updates.status is not None:
        milestone.status = updates.status
    if updates.order is not None:
        milestone.order = updates.order

    await db.commit()
    await schedule_checkin_for_milestone(db, milestone)
    await db.commit()
    await db.refresh(milestone)

    return MilestoneResponse(
        id=milestone.id,
        goal_id=milestone.goal_id,
        title=milestone.title,
        description=milestone.description,
        due_date=milestone.due_date,
        status=milestone.status.value,
        order=milestone.order,
        created_at=milestone.created_at
    )
