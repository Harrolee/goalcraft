from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.database import get_db
from app.models.schemas import Goal, Milestone, User, MilestoneStatus
from app.services.claude_service import ClaudeService
from app.services.calendar_service import CalendarService
from app.services.auth0 import get_current_user
from app.services.checkin_scheduler import schedule_checkin_for_milestone


router = APIRouter(prefix="/goals", tags=["goals"])


# Pydantic models for request/response
class MilestoneResponse(BaseModel):
    """Response model for a milestone."""
    id: int
    title: str
    description: Optional[str] = None
    due_date: Optional[datetime] = None
    status: str
    order: int
    created_at: datetime

    class Config:
        from_attributes = True


class GoalCreate(BaseModel):
    """Request model for creating a goal."""
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    target_date: Optional[datetime] = None


class GoalResponse(BaseModel):
    """Response model for a goal."""
    id: int
    user_id: int
    title: str
    description: Optional[str] = None
    target_date: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class GoalWithMilestones(GoalResponse):
    """Response model for a goal with its milestones."""
    milestones: List[MilestoneResponse] = []


@router.post("", response_model=GoalWithMilestones, status_code=status.HTTP_201_CREATED)
async def create_goal(
    goal_data: GoalCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> GoalWithMilestones:
    """
    Create a new goal and generate milestones using Claude.
    """
    # Create the goal
    goal = Goal(
        user_id=current_user.id,
        title=goal_data.title,
        description=goal_data.description,
        target_date=goal_data.target_date
    )
    db.add(goal)
    await db.commit()
    await db.refresh(goal)

    # Generate milestones using Claude
    claude = ClaudeService()
    goal_description = f"{goal_data.title}"
    if goal_data.description:
        goal_description += f": {goal_data.description}"

    try:
        milestone_data_list = await claude.plan_goal(goal_description, goal_data.target_date)

        # Create milestones in DB
        for md in milestone_data_list:
            milestone = Milestone(
                goal_id=goal.id,
                title=md.title,
                description=md.description,
                due_date=datetime.fromisoformat(md.due_date) if md.due_date else None,
                status=MilestoneStatus.PENDING,
                order=md.order
            )
            db.add(milestone)

        await db.commit()

        # Reload milestones to get their IDs for calendar + check-ins
        result = await db.execute(
            select(Milestone).where(Milestone.goal_id == goal.id).order_by(Milestone.order)
        )
        created_milestones = result.scalars().all()

        # Create calendar events if user has Google Calendar connected
        if current_user.google_refresh_token and current_user.google_calendar_id:
            try:
                calendar_service = CalendarService()

                for milestone in created_milestones:
                    if milestone.due_date:
                        event = await calendar_service.create_milestone_event(
                            refresh_token=current_user.google_refresh_token,
                            calendar_id=current_user.google_calendar_id,
                            title=milestone.title,
                            description=milestone.description or "",
                            due_date=milestone.due_date,
                            goal_title=goal_data.title
                        )
                        milestone.calendar_event_id = event.id

                await db.commit()
            except Exception as cal_error:
                print(f"Error creating calendar events: {cal_error}")

        # Schedule check-ins one day before each milestone
        for milestone in created_milestones:
            await schedule_checkin_for_milestone(db, milestone)
        await db.commit()

    except Exception as e:
        # Log error but don't fail the goal creation
        print(f"Error generating milestones: {e}")

    # Reload goal with milestones
    result = await db.execute(
        select(Goal)
        .options(selectinload(Goal.milestones))
        .where(Goal.id == goal.id)
    )
    goal = result.scalar_one()

    return GoalWithMilestones(
        id=goal.id,
        user_id=goal.user_id,
        title=goal.title,
        description=goal.description,
        target_date=goal.target_date,
        created_at=goal.created_at,
        milestones=[
            MilestoneResponse(
                id=m.id,
                title=m.title,
                description=m.description,
                due_date=m.due_date,
                status=m.status.value,
                order=m.order,
                created_at=m.created_at
            )
            for m in goal.milestones
        ]
    )


@router.get("", response_model=List[GoalResponse])
async def list_goals(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[GoalResponse]:
    """
    List all goals for the current user.
    """
    result = await db.execute(
        select(Goal)
        .where(Goal.user_id == current_user.id)
        .order_by(Goal.created_at.desc())
    )
    goals = result.scalars().all()

    return [
        GoalResponse(
            id=g.id,
            user_id=g.user_id,
            title=g.title,
            description=g.description,
            target_date=g.target_date,
            created_at=g.created_at
        )
        for g in goals
    ]


@router.get("/{goal_id}", response_model=GoalWithMilestones)
async def get_goal(
    goal_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> GoalWithMilestones:
    """
    Get a specific goal with its milestones.
    """
    result = await db.execute(
        select(Goal)
        .options(selectinload(Goal.milestones))
        .where(Goal.id == goal_id, Goal.user_id == current_user.id)
    )
    goal = result.scalar_one_or_none()

    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Goal with id {goal_id} not found"
        )

    return GoalWithMilestones(
        id=goal.id,
        user_id=goal.user_id,
        title=goal.title,
        description=goal.description,
        target_date=goal.target_date,
        created_at=goal.created_at,
        milestones=[
            MilestoneResponse(
                id=m.id,
                title=m.title,
                description=m.description,
                due_date=m.due_date,
                status=m.status.value,
                order=m.order,
                created_at=m.created_at
            )
            for m in goal.milestones
        ]
    )


@router.delete("/{goal_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_goal(
    goal_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Delete a goal and all its milestones.
    """
    result = await db.execute(
        select(Goal).where(Goal.id == goal_id, Goal.user_id == current_user.id)
    )
    goal = result.scalar_one_or_none()

    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Goal with id {goal_id} not found"
        )

    await db.delete(goal)
    await db.commit()


@router.post("/{goal_id}/sync-calendar")
async def sync_goal_to_calendar(
    goal_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> dict:
    """
    Sync all milestones for a goal to Google Calendar.
    Creates events for milestones that don't have calendar events yet.
    """
    result = await db.execute(
        select(Goal)
        .options(selectinload(Goal.milestones), selectinload(Goal.user))
        .where(Goal.id == goal_id, Goal.user_id == current_user.id)
    )
    goal = result.scalar_one_or_none()

    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Goal with id {goal_id} not found"
        )

    if not goal.user or not goal.user.google_refresh_token or not goal.user.google_calendar_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Google Calendar not connected. Please connect in Settings."
        )

    # Find milestones without calendar events
    milestones_to_sync = [
        m for m in goal.milestones
        if not m.calendar_event_id and m.due_date
    ]

    if not milestones_to_sync:
        return {"synced": 0, "message": "All milestones already synced"}

    calendar_service = CalendarService()
    synced_count = 0

    try:
        for milestone in milestones_to_sync:
            event = await calendar_service.create_milestone_event(
                refresh_token=goal.user.google_refresh_token,
                calendar_id=goal.user.google_calendar_id,
                title=milestone.title,
                description=milestone.description or "",
                due_date=milestone.due_date,
                goal_title=goal.title
            )
            milestone.calendar_event_id = event.id
            synced_count += 1

        await db.commit()

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error syncing to calendar: {str(e)}"
        )

    return {
        "synced": synced_count,
        "message": f"Synced {synced_count} milestones to Google Calendar"
    }
