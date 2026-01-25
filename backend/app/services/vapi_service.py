"""Service for VAPI voice call operations for goal check-ins."""

import logging
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Any, Dict, Optional

import httpx

from app.config import get_settings


logger = logging.getLogger(__name__)


class CallStatus(str, Enum):
    """VAPI call status values."""
    QUEUED = "queued"
    RINGING = "ringing"
    IN_PROGRESS = "in-progress"
    FORWARDING = "forwarding"
    ENDED = "ended"


@dataclass
class CallResult:
    """Data class for call initiation result."""
    success: bool
    call_id: Optional[str] = None
    error: Optional[str] = None


@dataclass
class CheckInCallResponse:
    """Data class for processed check-in call response."""
    call_id: str
    milestone_id: int
    transcript: Optional[str] = None
    summary: Optional[str] = None
    is_positive: bool = False
    ended_reason: Optional[str] = None
    received_at: Optional[datetime] = None


class VapiService:
    """Service for making outbound voice calls via VAPI for goal check-ins.

    This service handles:
    - Initiating outbound check-in calls with transient assistant configuration
    - Processing webhook events (status updates, end-of-call reports)
    - Tracking call progress and extracting check-in data
    """

    VAPI_API_BASE = "https://api.vapi.ai"

    def __init__(self):
        settings = get_settings()
        self.api_key = settings.VAPI_API_KEY
        self.phone_number_id = settings.VAPI_PHONE_NUMBER_ID
        self.callback_base_url = settings.CALLBACK_BASE_URL
        self._http_client: Optional[httpx.AsyncClient] = None

    async def _get_client(self) -> httpx.AsyncClient:
        """Get or create async HTTP client."""
        if self._http_client is None or self._http_client.is_closed:
            self._http_client = httpx.AsyncClient(
                base_url=self.VAPI_API_BASE,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                timeout=30.0,
            )
        return self._http_client

    def _build_system_prompt(
        self,
        user_name: str,
        goal_title: str,
        milestone_title: str,
        days_until_due: int,
    ) -> str:
        """Build the system prompt for the check-in voice assistant."""
        if days_until_due < 0:
            time_context = f"was due {abs(days_until_due)} day(s) ago"
        elif days_until_due == 0:
            time_context = "is due today"
        elif days_until_due == 1:
            time_context = "is due tomorrow"
        else:
            time_context = f"is due in {days_until_due} days"

        return f"""You are a friendly and encouraging goal accountability assistant for GoalCraft.

You are calling {user_name} to check on their progress toward a goal.

## Goal Information
- Goal: {goal_title}
- Current Milestone: {milestone_title}
- Status: The milestone {time_context}

## Your Task
1. Greet the user warmly by name
2. Ask how their progress is going on the current milestone
3. Listen to their response and acknowledge it
4. If they're making progress, offer encouragement
5. If they're struggling, offer empathy and a brief motivational thought
6. Thank them for the update and wish them well
7. End the call politely

## Guidelines
- Keep the call brief (under 2 minutes)
- Be warm, supportive, and non-judgmental
- Don't be pushy or make them feel guilty
- If they seem busy, offer to call back another time
- Use a conversational, natural tone

## Important
- This is a check-in call, not a sales call
- Your goal is to help them stay accountable and motivated
- End the call when the conversation naturally concludes"""

    def _build_assistant_config(
        self,
        user_name: str,
        goal_title: str,
        milestone_title: str,
        milestone_id: int,
        days_until_due: int,
    ) -> Dict[str, Any]:
        """Build transient assistant configuration for the check-in call."""
        system_prompt = self._build_system_prompt(
            user_name=user_name,
            goal_title=goal_title,
            milestone_title=milestone_title,
            days_until_due=days_until_due,
        )

        webhook_url = f"{self.callback_base_url}/api/v1/vapi-webhook"

        return {
            "name": "GoalCraft Check-in Assistant",
            "model": {
                "provider": "openai",
                "model": "gpt-4o-mini",
                "temperature": 0.7,
                "messages": [{"role": "system", "content": system_prompt}],
            },
            "voice": {
                "provider": "11labs",
                "voiceId": "21m00Tcm4TlvDq8ikWAM",  # Rachel - friendly, warm voice
            },
            "firstMessage": f"Hi {user_name}! This is your GoalCraft check-in call. I wanted to see how you're doing with your goal. Is now a good time to chat for a minute?",
            "serverUrl": webhook_url,
            "silenceTimeoutSeconds": 30,
            "maxDurationSeconds": 180,  # 3 minute max
            "backgroundSound": "off",
            "endCallMessage": "Thanks for chatting! Keep up the great work on your goals. Goodbye!",
            "startSpeakingPlan": {
                "waitSeconds": 0.5,
                "transcriptionEndpointingPlan": {
                    "onNoPunctuationSeconds": 1.5,
                },
            },
            "stopSpeakingPlan": {
                "numWords": 3,
                "backoffSeconds": 1.0,
            },
        }

    async def initiate_checkin_call(
        self,
        to_number: str,
        user_name: str,
        goal_title: str,
        milestone_title: str,
        milestone_id: int,
        due_date: datetime,
    ) -> CallResult:
        """
        Initiate an outbound check-in call via VAPI.

        Args:
            to_number: Recipient phone number in E.164 format
            user_name: User's name for personalized greeting
            goal_title: Title of the goal being checked on
            milestone_title: Title of the current milestone
            milestone_id: ID of the milestone for tracking
            due_date: Due date of the milestone

        Returns:
            CallResult with success status and call ID or error
        """
        days_until_due = (due_date.date() - datetime.now().date()).days

        logger.info(
            f"Initiating VAPI check-in call to {self._mask_phone(to_number)} "
            f"for milestone {milestone_id}"
        )

        # Build assistant configuration
        assistant_config = self._build_assistant_config(
            user_name=user_name,
            goal_title=goal_title,
            milestone_title=milestone_title,
            milestone_id=milestone_id,
            days_until_due=days_until_due,
        )

        # Build the API request
        request_payload = {
            "assistant": assistant_config,
            "phoneNumberId": self.phone_number_id,
            "customer": {
                "number": to_number,
                "name": user_name,
            },
            "metadata": {
                "milestone_id": str(milestone_id),
                "goal_title": goal_title,
                "milestone_title": milestone_title,
                "user_name": user_name,
            },
        }

        try:
            client = await self._get_client()
            response = await client.post("/call", json=request_payload)
            response.raise_for_status()

            result = response.json()
            call_id = result.get("id")

            logger.info(
                f"VAPI check-in call initiated - call_id: {call_id}, "
                f"milestone_id: {milestone_id}"
            )

            return CallResult(success=True, call_id=call_id)

        except httpx.HTTPStatusError as e:
            error_msg = f"VAPI API error: {e.response.status_code} - {e.response.text}"
            logger.error(error_msg)
            return CallResult(success=False, error=error_msg)
        except Exception as e:
            error_msg = f"Failed to initiate VAPI call: {str(e)}"
            logger.error(error_msg, exc_info=True)
            return CallResult(success=False, error=error_msg)

    async def get_call_status(self, call_id: str) -> Optional[Dict[str, Any]]:
        """
        Get the current status of a call.

        Args:
            call_id: The VAPI call ID

        Returns:
            Dict with call status information, or None if not found
        """
        try:
            client = await self._get_client()
            response = await client.get(f"/call/{call_id}")
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                return None
            logger.error(f"Error getting call status: {e}")
            raise
        except Exception as e:
            logger.error(f"Error getting call status: {e}")
            raise

    async def stop_call(self, call_id: str) -> Dict[str, Any]:
        """
        Stop/end an active VAPI call.

        Args:
            call_id: The VAPI call ID to stop

        Returns:
            Dict with call_id, status, and message

        Raises:
            httpx.HTTPStatusError: If VAPI API returns an error
        """
        logger.info(f"Stopping VAPI call {call_id}")

        try:
            client = await self._get_client()
            response = await client.delete(f"/call/{call_id}")
            response.raise_for_status()

            result = response.json()
            status = result.get("status", "ended")

            logger.info(f"VAPI call {call_id} stopped successfully, status: {status}")

            return {
                "call_id": call_id,
                "status": status,
                "message": "Call stopped successfully",
            }

        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                return {
                    "call_id": call_id,
                    "status": "not_found",
                    "message": "Call not found or already ended",
                }
            logger.error(
                f"VAPI API error stopping call {call_id}: "
                f"{e.response.status_code} - {e.response.text}"
            )
            raise
        except Exception as e:
            logger.error(f"Failed to stop VAPI call {call_id}: {e}", exc_info=True)
            raise

    def process_status_update(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process a status-update webhook event.

        Args:
            payload: The webhook payload from VAPI

        Returns:
            Dict with processed status information
        """
        call_id = payload.get("call", {}).get("id")
        status = payload.get("status")

        logger.info(f"[VAPI {call_id}] Status update: {status}")

        return {
            "call_id": call_id,
            "status": status,
            "timestamp": datetime.now().isoformat(),
        }

    def process_end_of_call_report(
        self, payload: Dict[str, Any]
    ) -> CheckInCallResponse:
        """
        Process an end-of-call-report webhook event.

        Args:
            payload: The webhook payload from VAPI

        Returns:
            CheckInCallResponse with extracted check-in data
        """
        call_data = payload.get("call", {})
        call_id = call_data.get("id")
        metadata = call_data.get("metadata", {})

        transcript = payload.get("transcript", "")
        summary = payload.get("summary", "")
        ended_reason = payload.get("endedReason")

        milestone_id = int(metadata.get("milestone_id", 0))

        logger.info(f"[VAPI {call_id}] Call ended: {ended_reason}")

        # Analyze transcript for positive sentiment
        is_positive = self._analyze_sentiment(transcript)

        return CheckInCallResponse(
            call_id=call_id,
            milestone_id=milestone_id,
            transcript=transcript,
            summary=summary,
            is_positive=is_positive,
            ended_reason=ended_reason,
            received_at=datetime.now(),
        )

    def _analyze_sentiment(self, transcript: str) -> bool:
        """
        Simple sentiment analysis on the transcript.

        Args:
            transcript: The call transcript

        Returns:
            True if the sentiment seems positive/progress-oriented
        """
        if not transcript:
            return False

        transcript_lower = transcript.lower()

        positive_indicators = [
            "done", "completed", "finished", "progress", "working on",
            "almost there", "making progress", "good", "great", "yes",
            "on track", "ahead", "excited", "motivated"
        ]

        negative_indicators = [
            "stuck", "behind", "struggling", "haven't started",
            "no progress", "difficult", "hard time", "can't", "won't"
        ]

        positive_count = sum(
            1 for indicator in positive_indicators if indicator in transcript_lower
        )
        negative_count = sum(
            1 for indicator in negative_indicators if indicator in transcript_lower
        )

        return positive_count > negative_count

    def _mask_phone(self, phone: str) -> str:
        """Mask phone number for logging."""
        if len(phone) < 4:
            return "****"
        return "*" * (len(phone) - 4) + phone[-4:]

    async def close(self) -> None:
        """Close HTTP client."""
        if self._http_client and not self._http_client.is_closed:
            await self._http_client.aclose()
            self._http_client = None


# Singleton instance for FastAPI dependency injection
_vapi_service: Optional[VapiService] = None


def get_vapi_service() -> VapiService:
    """Get or create the VAPI service singleton."""
    global _vapi_service
    if _vapi_service is None:
        _vapi_service = VapiService()
    return _vapi_service
