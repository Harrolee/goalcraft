"""
VAPI Webhook Routes for GoalCraft

This module handles incoming webhook events from VAPI:
- status-update: Call status changes (ringing, in-progress, ended)
- end-of-call-report: Final call report with transcript and summary

These webhooks are called by VAPI during and after voice calls to provide
real-time updates and final call data for processing.
"""

import logging
from datetime import datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from app.services.vapi_service import get_vapi_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/vapi-webhook", tags=["vapi-webhook"])


class VapiWebhookPayload(BaseModel):
    """Base model for VAPI webhook payloads."""
    message: Dict[str, Any]


class StatusUpdateMessage(BaseModel):
    """Model for status-update webhook message."""
    type: str
    status: str
    call: Optional[Dict[str, Any]] = None
    timestamp: Optional[str] = None


class EndOfCallReportMessage(BaseModel):
    """Model for end-of-call-report webhook message."""
    type: str
    call: Dict[str, Any]
    endedReason: Optional[str] = None
    transcript: Optional[str] = None
    summary: Optional[str] = None
    recordingUrl: Optional[str] = None
    messages: Optional[list] = None


def get_db():
    """
    Database session dependency.
    Replace this with your actual database session factory.
    """
    raise NotImplementedError("Replace with your actual database session dependency")


@router.post("")
async def vapi_webhook(request: Request):
    """
    Main VAPI webhook endpoint.

    This endpoint receives all webhook events from VAPI and routes them
    to the appropriate handler based on the message type.

    VAPI sends the following message types:
    - status-update: When call status changes
    - end-of-call-report: When call ends with full transcript
    - transcript: Real-time transcript updates (optional)
    - hang: When user/assistant hangs up
    - speech-update: Speech detection events

    Returns:
        Acknowledgment response or error
    """
    try:
        payload = await request.json()
        message = payload.get("message", {})
        message_type = message.get("type", "unknown")

        logger.info(f"VAPI webhook received: {message_type}")

        # Route to appropriate handler
        if message_type == "status-update":
            return await handle_status_update(message)
        elif message_type == "end-of-call-report":
            return await handle_end_of_call_report(message)
        elif message_type == "transcript":
            return await handle_transcript_update(message)
        elif message_type == "hang":
            return await handle_hang(message)
        else:
            logger.debug(f"Unhandled webhook type: {message_type}")
            return {"status": "ok", "message": f"Unhandled type: {message_type}"}

    except Exception as e:
        logger.error(f"Error processing VAPI webhook: {e}", exc_info=True)
        # Return 200 to prevent VAPI from retrying
        return {"status": "error", "message": str(e)}


async def handle_status_update(message: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle status-update webhook event.

    This is called when the call status changes:
    - queued: Call is queued
    - ringing: Phone is ringing
    - in-progress: Call is connected
    - forwarding: Call is being forwarded
    - ended: Call has ended

    Args:
        message: The webhook message payload

    Returns:
        Acknowledgment response
    """
    call_data = message.get("call", {})
    call_id = call_data.get("id")
    status = message.get("status")
    metadata = call_data.get("metadata", {})
    milestone_id = metadata.get("milestone_id")

    logger.info(
        f"[VAPI {call_id}] Status update: {status} "
        f"(milestone_id={milestone_id})"
    )

    vapi_service = get_vapi_service()
    result = vapi_service.process_status_update(message)

    # Update database if configured
    """
    if status == "in-progress":
        # Update check-in status to 'in_progress'
        db.query(CheckIn).filter(
            CheckIn.call_id == call_id
        ).update({"status": "in_progress", "call_connected_at": datetime.utcnow()})
        db.commit()
    elif status == "ended":
        # Will be handled by end-of-call-report
        pass
    """

    return {"status": "ok", "processed": result}


async def handle_end_of_call_report(message: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle end-of-call-report webhook event.

    This is called when a call ends and contains:
    - Full transcript of the conversation
    - AI-generated summary
    - Recording URL (if enabled)
    - Call metadata

    This is where we extract check-in response data and update the database.

    Args:
        message: The webhook message payload

    Returns:
        Acknowledgment response
    """
    call_data = message.get("call", {})
    call_id = call_data.get("id")
    metadata = call_data.get("metadata", {})
    milestone_id = metadata.get("milestone_id")

    ended_reason = message.get("endedReason")
    transcript = message.get("transcript", "")
    summary = message.get("summary", "")
    recording_url = message.get("recordingUrl")

    logger.info(
        f"[VAPI {call_id}] End of call report: "
        f"reason={ended_reason}, transcript_length={len(transcript)}, "
        f"milestone_id={milestone_id}"
    )

    vapi_service = get_vapi_service()
    response = vapi_service.process_end_of_call_report(message)

    logger.info(
        f"[VAPI {call_id}] Processed check-in response: "
        f"is_positive={response.is_positive}, milestone_id={response.milestone_id}"
    )

    # Update database if configured
    """
    checkin = db.query(CheckIn).filter(
        CheckIn.milestone_id == milestone_id,
        CheckIn.status == 'in_progress'
    ).order_by(CheckIn.created_at.desc()).first()

    if checkin:
        checkin.status = 'completed'
        checkin.response = transcript
        checkin.summary = summary
        checkin.is_positive = response.is_positive
        checkin.call_ended_at = datetime.utcnow()
        checkin.ended_reason = ended_reason
        checkin.recording_url = recording_url

        db.commit()

        logger.info(f"Updated check-in {checkin.id} with call results")
    """

    return {
        "status": "ok",
        "call_id": call_id,
        "milestone_id": response.milestone_id,
        "is_positive": response.is_positive,
    }


async def handle_transcript_update(message: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle real-time transcript updates.

    These are sent during the call as speech is transcribed.
    Useful for real-time monitoring but not essential for check-ins.

    Args:
        message: The webhook message payload

    Returns:
        Acknowledgment response
    """
    call_data = message.get("call", {})
    call_id = call_data.get("id")
    transcript = message.get("transcript", "")

    logger.debug(f"[VAPI {call_id}] Transcript update: {transcript[:100]}...")

    return {"status": "ok"}


async def handle_hang(message: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle hang event (when user or assistant ends the call).

    Args:
        message: The webhook message payload

    Returns:
        Acknowledgment response
    """
    call_data = message.get("call", {})
    call_id = call_data.get("id")

    logger.info(f"[VAPI {call_id}] Call hang event received")

    return {"status": "ok"}


@router.get("/health")
async def webhook_health():
    """
    Health check endpoint for VAPI webhook.

    Returns:
        Health status
    """
    return {
        "status": "healthy",
        "service": "vapi-webhook",
        "timestamp": datetime.utcnow().isoformat(),
    }
