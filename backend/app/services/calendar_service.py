from datetime import datetime, timedelta
from typing import List, Optional
from dataclasses import dataclass

from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build

from app.config import get_settings


GOALCRAFT_CALENDAR_NAME = "GoalCraft"
GOALCRAFT_CALENDAR_DESCRIPTION = "Milestones and deadlines from GoalCraft"


@dataclass
class CalendarEvent:
    """Data class for calendar event information."""
    id: str
    summary: str
    description: str
    start: datetime
    end: datetime
    html_link: str


@dataclass
class CalendarInfo:
    """Data class for calendar information."""
    id: str
    name: str


class CalendarService:
    """Service for Google Calendar API integration."""

    # Need full calendar scope to create calendars
    SCOPES = ["https://www.googleapis.com/auth/calendar"]

    def __init__(self):
        settings = get_settings()
        self.client_id = settings.GOOGLE_CLIENT_ID
        self.client_secret = settings.GOOGLE_CLIENT_SECRET

    def get_oauth_flow(self, redirect_uri: str) -> Flow:
        """
        Create an OAuth flow for Google Calendar authorization.

        Args:
            redirect_uri: The URI to redirect to after authorization

        Returns:
            Flow object for handling OAuth
        """
        client_config = {
            "web": {
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
            }
        }

        flow = Flow.from_client_config(
            client_config,
            scopes=self.SCOPES,
            redirect_uri=redirect_uri
        )

        return flow

    def get_credentials_from_refresh_token(self, refresh_token: str) -> Credentials:
        """
        Create credentials from a stored refresh token.

        Args:
            refresh_token: The user's stored refresh token

        Returns:
            Credentials object for API calls
        """
        return Credentials(
            token=None,
            refresh_token=refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=self.client_id,
            client_secret=self.client_secret,
            scopes=self.SCOPES
        )

    def _get_service(self, refresh_token: str):
        """Build and return the Google Calendar service."""
        credentials = self.get_credentials_from_refresh_token(refresh_token)
        return build("calendar", "v3", credentials=credentials)

    async def get_or_create_goalcraft_calendar(
        self,
        refresh_token: str,
        existing_calendar_id: Optional[str] = None
    ) -> CalendarInfo:
        """
        Get or create the dedicated GoalCraft calendar.

        Args:
            refresh_token: User's Google refresh token
            existing_calendar_id: Previously stored calendar ID (if any)

        Returns:
            CalendarInfo with the calendar ID and name
        """
        service = self._get_service(refresh_token)

        # If we have an existing ID, verify it still exists
        if existing_calendar_id:
            try:
                calendar = service.calendars().get(calendarId=existing_calendar_id).execute()
                return CalendarInfo(id=calendar["id"], name=calendar.get("summary", GOALCRAFT_CALENDAR_NAME))
            except Exception:
                # Calendar doesn't exist anymore, create a new one
                pass

        # Search for existing GoalCraft calendar
        calendar_list = service.calendarList().list().execute()
        for cal in calendar_list.get("items", []):
            if cal.get("summary") == GOALCRAFT_CALENDAR_NAME:
                return CalendarInfo(id=cal["id"], name=cal["summary"])

        # Create new GoalCraft calendar
        calendar_body = {
            "summary": GOALCRAFT_CALENDAR_NAME,
            "description": GOALCRAFT_CALENDAR_DESCRIPTION,
            "timeZone": "UTC"
        }
        new_calendar = service.calendars().insert(body=calendar_body).execute()

        return CalendarInfo(id=new_calendar["id"], name=new_calendar["summary"])

    async def create_milestone_event(
        self,
        refresh_token: str,
        calendar_id: str,
        title: str,
        description: str,
        due_date: datetime,
        goal_title: str
    ) -> CalendarEvent:
        """
        Create a single calendar event for a milestone.

        Args:
            refresh_token: User's Google refresh token
            calendar_id: ID of the GoalCraft calendar
            title: Milestone title
            description: Milestone description
            due_date: Due date for the milestone
            goal_title: Title of the parent goal

        Returns:
            Created CalendarEvent
        """
        service = self._get_service(refresh_token)

        event_body = {
            "summary": f"[{goal_title}] {title}",
            "description": description or "",
            "start": {
                "date": due_date.strftime("%Y-%m-%d"),
            },
            "end": {
                "date": due_date.strftime("%Y-%m-%d"),
            },
            "reminders": {
                "useDefault": False,
                "overrides": [
                    {"method": "popup", "minutes": 1440},  # 1 day before
                    {"method": "popup", "minutes": 60},    # 1 hour before
                ],
            },
        }

        event = service.events().insert(
            calendarId=calendar_id,
            body=event_body
        ).execute()

        return CalendarEvent(
            id=event["id"],
            summary=event["summary"],
            description=event.get("description", ""),
            start=due_date,
            end=due_date,
            html_link=event.get("htmlLink", "")
        )

    async def create_milestone_events(
        self,
        refresh_token: str,
        calendar_id: str,
        milestones: List[dict],
        goal_title: str
    ) -> List[CalendarEvent]:
        """
        Create calendar events for multiple milestones.

        Args:
            refresh_token: User's Google refresh token
            calendar_id: ID of the GoalCraft calendar
            milestones: List of milestone dictionaries with title, description, due_date
            goal_title: Title of the parent goal

        Returns:
            List of created CalendarEvent objects
        """
        created_events = []

        for milestone in milestones:
            due_date = milestone["due_date"]
            if isinstance(due_date, str):
                due_date = datetime.fromisoformat(due_date)

            event = await self.create_milestone_event(
                refresh_token=refresh_token,
                calendar_id=calendar_id,
                title=milestone["title"],
                description=milestone.get("description", ""),
                due_date=due_date,
                goal_title=goal_title
            )
            created_events.append(event)

        return created_events

    async def get_event(
        self,
        refresh_token: str,
        calendar_id: str,
        event_id: str
    ) -> Optional[CalendarEvent]:
        """
        Get a single calendar event.

        Args:
            refresh_token: User's Google refresh token
            calendar_id: ID of the GoalCraft calendar
            event_id: ID of the event to get

        Returns:
            CalendarEvent or None if not found
        """
        service = self._get_service(refresh_token)

        try:
            event = service.events().get(
                calendarId=calendar_id,
                eventId=event_id
            ).execute()

            start_str = event["start"].get("date", event["start"].get("dateTime", ""))[:10]
            start_date = datetime.fromisoformat(start_str)

            return CalendarEvent(
                id=event["id"],
                summary=event["summary"],
                description=event.get("description", ""),
                start=start_date,
                end=start_date,
                html_link=event.get("htmlLink", "")
            )
        except Exception:
            return None

    async def update_milestone_event(
        self,
        refresh_token: str,
        calendar_id: str,
        event_id: str,
        updates: dict,
        goal_title: Optional[str] = None
    ) -> Optional[CalendarEvent]:
        """
        Update an existing calendar event.

        Args:
            refresh_token: User's Google refresh token
            calendar_id: ID of the GoalCraft calendar
            event_id: ID of the event to update
            updates: Dictionary of fields to update (title, description, due_date, status)
            goal_title: Goal title for formatting the event summary

        Returns:
            Updated CalendarEvent or None if not found
        """
        service = self._get_service(refresh_token)

        try:
            # Get existing event
            event = service.events().get(
                calendarId=calendar_id,
                eventId=event_id
            ).execute()

            # Apply updates
            if "title" in updates:
                if goal_title:
                    event["summary"] = f"[{goal_title}] {updates['title']}"
                else:
                    event["summary"] = updates["title"]

            if "description" in updates:
                event["description"] = updates["description"]

            if "due_date" in updates:
                due_date = updates["due_date"]
                if isinstance(due_date, str):
                    due_date = datetime.fromisoformat(due_date)
                event["start"]["date"] = due_date.strftime("%Y-%m-%d")
                event["end"]["date"] = due_date.strftime("%Y-%m-%d")

            # If status is completed, add a checkmark to the title
            if "status" in updates and updates["status"] == "completed":
                if not event["summary"].startswith("✓"):
                    event["summary"] = f"✓ {event['summary']}"
            elif "status" in updates and updates["status"] == "pending":
                # Remove checkmark if going back to pending
                if event["summary"].startswith("✓ "):
                    event["summary"] = event["summary"][2:]

            # Update event
            updated_event = service.events().update(
                calendarId=calendar_id,
                eventId=event_id,
                body=event
            ).execute()

            start_str = updated_event["start"].get("date", updated_event["start"].get("dateTime", ""))[:10]
            start_date = datetime.fromisoformat(start_str)

            return CalendarEvent(
                id=updated_event["id"],
                summary=updated_event["summary"],
                description=updated_event.get("description", ""),
                start=start_date,
                end=start_date,
                html_link=updated_event.get("htmlLink", "")
            )
        except Exception as e:
            print(f"Error updating calendar event: {e}")
            return None

    async def delete_milestone_event(
        self,
        refresh_token: str,
        calendar_id: str,
        event_id: str
    ) -> bool:
        """
        Delete a calendar event.

        Args:
            refresh_token: User's Google refresh token
            calendar_id: ID of the GoalCraft calendar
            event_id: ID of the event to delete

        Returns:
            True if deleted successfully, False otherwise
        """
        service = self._get_service(refresh_token)

        try:
            service.events().delete(
                calendarId=calendar_id,
                eventId=event_id
            ).execute()
            return True
        except Exception as e:
            print(f"Error deleting calendar event: {e}")
            return False

    async def list_events(
        self,
        refresh_token: str,
        calendar_id: str,
        time_min: Optional[datetime] = None,
        time_max: Optional[datetime] = None,
        max_results: int = 100
    ) -> List[CalendarEvent]:
        """
        List events from the GoalCraft calendar.

        Args:
            refresh_token: User's Google refresh token
            calendar_id: ID of the GoalCraft calendar
            time_min: Start of time range (defaults to now)
            time_max: End of time range
            max_results: Maximum number of events to return

        Returns:
            List of CalendarEvent objects
        """
        service = self._get_service(refresh_token)

        if time_min is None:
            time_min = datetime.now()

        params = {
            "calendarId": calendar_id,
            "timeMin": time_min.isoformat() + "Z",
            "maxResults": max_results,
            "singleEvents": True,
            "orderBy": "startTime"
        }

        if time_max:
            params["timeMax"] = time_max.isoformat() + "Z"

        try:
            events_result = service.events().list(**params).execute()
            events = []

            for event in events_result.get("items", []):
                start_str = event["start"].get("date", event["start"].get("dateTime", ""))[:10]
                start_date = datetime.fromisoformat(start_str)

                events.append(CalendarEvent(
                    id=event["id"],
                    summary=event.get("summary", ""),
                    description=event.get("description", ""),
                    start=start_date,
                    end=start_date,
                    html_link=event.get("htmlLink", "")
                ))

            return events
        except Exception as e:
            print(f"Error listing calendar events: {e}")
            return []
