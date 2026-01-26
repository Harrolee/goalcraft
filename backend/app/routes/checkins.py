"""
GoalCraft Check-ins API Routes

This module provides endpoints for:
- POST /check-ins/trigger - Cloud Scheduler endpoint to process due check-ins
- GET /check-ins/status - Check-in system status

The check-in system initiates VAPI voice calls to users asking about their
goal progress and records their responses for AI coaching analysis.
"""

import logging
from datetime import datetime

from fastapi import APIRouter, HTTPException, Request, Depends
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.database import get_db
from app.models.schemas import CheckIn, CheckInStatus, Milestone, Goal
from app.services.vapi_service import get_vapi_service, VapiService, CallResult

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/check-ins", tags=["check-ins"])


async def initiate_checkin_call(
    vapi_service: VapiService,
    to_number: str,
    user_name: str,
    goal_title: str,
    milestone_title: str,
    milestone_id: int,
    due_date: datetime,
) -> CallResult:
    """
    Initiate a check-in voice call via VAPI.

    Args:
        vapi_service: The VAPI service instance
        to_number: The recipient's phone number in E.164 format
        user_name: User's name for personalized greeting
        goal_title: Title of the goal
        milestone_title: Title of the milestone
        milestone_id: ID of the milestone
        due_date: Due date of the milestone

    Returns:
        True if the call was initiated successfully, False otherwise
    """
    return await vapi_service.initiate_checkin_call(
        to_number=to_number,
        user_name=user_name,
        goal_title=goal_title,
        milestone_title=milestone_title,
        milestone_id=milestone_id,
        due_date=due_date,
    )


@router.post("/trigger")
async def trigger_checkins(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Trigger check-in processing for all due check-ins.

    This endpoint is called by Google Cloud Scheduler every hour to:
    1. Find all check-ins that are due
    2. Initiate VAPI voice calls to users asking about their progress
    3. Update check-in status to 'calling'

    Authentication:
        This endpoint is protected by Cloud Run's IAM and should only be
        called by the Cloud Scheduler service account.

    Returns:
        Summary of processed check-ins
    """
    logger.info("Check-in trigger received")

    # Verify the request is from Cloud Scheduler (in production)
    # The scheduler uses OIDC authentication which Cloud Run validates

    try:
        # Get current time
        now = datetime.utcnow()

        # Get VAPI service
        vapi_service = get_vapi_service()

        result = await db.execute(
            select(CheckIn)
            .join(CheckIn.milestone)
            .join(Milestone.goal)
            .join(Goal.user)
            .options(
                selectinload(CheckIn.milestone)
                .selectinload(Milestone.goal)
                .selectinload(Goal.user)
            )
            .where(CheckIn.scheduled_at <= now, CheckIn.status == CheckInStatus.PENDING)
        )
        due_checkins = result.scalars().unique().all()

        processed = 0
        failed = 0

        for checkin in due_checkins:
            milestone = checkin.milestone
            goal = milestone.goal
            user = goal.user

            if not user or not user.phone_number or not milestone.due_date:
                checkin.status = CheckInStatus.FAILED
                failed += 1
                continue

            user_name = user.email.split("@")[0] if user.email else "there"

            call_result = await initiate_checkin_call(
                vapi_service=vapi_service,
                to_number=user.phone_number,
                user_name=user_name,
                goal_title=goal.title,
                milestone_title=milestone.title,
                milestone_id=milestone.id,
                due_date=milestone.due_date,
            )

            if call_result.success:
                checkin.status = CheckInStatus.CALLING
                checkin.sent_at = now
                checkin.call_id = call_result.call_id
                processed += 1
            else:
                checkin.status = CheckInStatus.FAILED
                failed += 1

        await db.commit()

        logger.info(f"Check-in processing complete. Processed: {processed}, Failed: {failed}")

        return {
            "status": "success",
            "processed": processed,
            "failed": failed,
            "timestamp": now.isoformat(),
        }

    except Exception as e:
        logger.error(f"Error processing check-ins: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error processing check-ins: {str(e)}"
        )


@router.post("/call/{milestone_id}")
async def trigger_single_checkin(
    milestone_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Trigger a check-in call for a specific milestone.

    This endpoint allows manually triggering a check-in call for testing
    or on-demand check-ins.

    Args:
        milestone_id: ID of the milestone to check in on

    Returns:
        Call initiation result
    """
    logger.info(f"Manual check-in trigger for milestone {milestone_id}")

    try:
        vapi_service = get_vapi_service()

        result = await db.execute(
            select(Milestone)
            .join(Milestone.goal)
            .join(Goal.user)
            .options(selectinload(Milestone.goal).selectinload(Goal.user))
            .where(Milestone.id == milestone_id)
        )
        milestone = result.scalar_one_or_none()
        if not milestone:
            raise HTTPException(status_code=404, detail="Milestone not found")

        goal = milestone.goal
        user = goal.user if goal else None

        if not user or not user.phone_number or not milestone.due_date:
            raise HTTPException(status_code=400, detail="User phone number or due date missing")

        user_name = user.email.split("@")[0] if user.email else "there"

        checkin = CheckIn(
            milestone_id=milestone.id,
            scheduled_at=datetime.utcnow(),
            status=CheckInStatus.PENDING,
        )
        db.add(checkin)
        await db.commit()
        await db.refresh(checkin)

        call_result = await vapi_service.initiate_checkin_call(
            to_number=user.phone_number,
            user_name=user_name,
            goal_title=goal.title,
            milestone_title=milestone.title,
            milestone_id=milestone.id,
            due_date=milestone.due_date,
        )

        if call_result.success:
            checkin.status = CheckInStatus.CALLING
            checkin.sent_at = datetime.utcnow()
            checkin.call_id = call_result.call_id
            await db.commit()
            return {
                "status": "success",
                "call_id": call_result.call_id,
                "milestone_id": milestone_id,
            }

        checkin.status = CheckInStatus.FAILED
        await db.commit()
        raise HTTPException(status_code=500, detail=call_result.error)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error triggering check-in call: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error triggering check-in call: {str(e)}"
        )


@router.get("/call/{call_id}/status")
async def get_call_status(call_id: str):
    """
    Get the status of a check-in call.

    Args:
        call_id: The VAPI call ID

    Returns:
        Call status information
    """
    try:
        vapi_service = get_vapi_service()
        status = await vapi_service.get_call_status(call_id)

        if status is None:
            raise HTTPException(status_code=404, detail="Call not found")

        return status

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting call status: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error getting call status: {str(e)}"
        )


@router.delete("/call/{call_id}")
async def stop_call(call_id: str):
    """
    Stop an active check-in call.

    Args:
        call_id: The VAPI call ID to stop

    Returns:
        Result of the stop operation
    """
    try:
        vapi_service = get_vapi_service()
        result = await vapi_service.stop_call(call_id)
        return result

    except Exception as e:
        logger.error(f"Error stopping call: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error stopping call: {str(e)}"
        )


@router.get("/status")
async def checkin_status():
    """
    Get check-in system status and statistics.

    Returns summary of:
    - VAPI configuration status
    - Recent check-in activity

    Returns:
        Check-in system status information
    """
    try:
        vapi_service = get_vapi_service()
        return {
            "vapi_configured": bool(vapi_service.api_key and vapi_service.phone_number_id),
            "callback_url": vapi_service.callback_base_url,
            "status": "operational",
            # Add database statistics when configured
            # "statistics": {
            #     "pending": db.query(CheckIn).filter(CheckIn.status == 'pending').count(),
            #     "calling": db.query(CheckIn).filter(CheckIn.status == 'calling').count(),
            #     "completed": db.query(CheckIn).filter(CheckIn.status == 'completed').count(),
            # }
        }
    except Exception as e:
        logger.error(f"Error getting check-in status: {e}")
        return {
            "vapi_configured": False,
            "status": "error",
            "error": str(e),
        }
