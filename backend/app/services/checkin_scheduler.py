from __future__ import annotations

from datetime import timedelta

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.schemas import CheckIn, CheckInStatus, Milestone, MilestoneStatus


async def clear_pending_checkins(db: AsyncSession, milestone_id: int) -> None:
    await db.execute(
        delete(CheckIn).where(
            CheckIn.milestone_id == milestone_id,
            CheckIn.status == CheckInStatus.PENDING,
        )
    )


async def schedule_checkin_for_milestone(
    db: AsyncSession,
    milestone: Milestone,
) -> CheckIn | None:
    await clear_pending_checkins(db, milestone.id)

    if not milestone.due_date:
        return None

    if milestone.status in {MilestoneStatus.COMPLETED, MilestoneStatus.SKIPPED}:
        return None

    scheduled_at = milestone.due_date - timedelta(days=1)
    checkin = CheckIn(
        milestone_id=milestone.id,
        scheduled_at=scheduled_at,
        status=CheckInStatus.PENDING,
    )
    db.add(checkin)
    return checkin
