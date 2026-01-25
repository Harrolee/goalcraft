import json
from contextlib import asynccontextmanager
from datetime import datetime
from typing import AsyncGenerator, List, Dict, Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, delete
from sqlalchemy.orm import selectinload

from app.routes import goals_router, milestones_router, auth_router
from app.models.database import AsyncSessionLocal
from app.models.schemas import Goal, Milestone, MilestoneStatus, ChatMessage, ChatRole, User
from app.services.claude_service import ClaudeService, ToolResult
from app.services.calendar_service import CalendarService


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler for startup and shutdown events."""
    # Run database initialization
    from app.models.database import init_db
    await init_db()
    yield


app = FastAPI(
    title="GoalCraft API",
    description="API for the GoalCraft goal planning application",
    version="1.0.0",
    lifespan=lifespan
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers with /api prefix
app.include_router(goals_router, prefix="/api")
app.include_router(milestones_router, prefix="/api")
app.include_router(auth_router, prefix="/api")


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint."""
    return {"status": "healthy", "service": "goalcraft-api"}


async def get_milestones_for_goal(goal_id: int) -> List[dict]:
    """Fetch current milestones for a goal from DB."""
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Milestone)
            .where(Milestone.goal_id == goal_id)
            .order_by(Milestone.order)
        )
        milestones = result.scalars().all()
        return [
            {
                "id": m.id,
                "title": m.title,
                "description": m.description,
                "due_date": m.due_date.isoformat() if m.due_date else None,
                "status": m.status.value,
                "order": m.order
            }
            for m in milestones
        ]


def create_tool_executor(
    goal_id: int,
    websocket: WebSocket,
    user_refresh_token: str | None = None,
    user_calendar_id: str | None = None,
    goal_title: str = ""
):
    """Create a tool executor function for milestone management."""

    async def execute_tool(tool_name: str, tool_input: Dict[str, Any]) -> ToolResult:
        """Execute a milestone management tool and return the result."""
        try:
            if tool_name == "get_milestones":
                milestones = await get_milestones_for_goal(goal_id)
                return ToolResult(
                    tool_use_id="",
                    content=json.dumps(milestones, indent=2)
                )

            elif tool_name == "add_milestone":
                async with AsyncSessionLocal() as db:
                    # Get the max order for this goal
                    result = await db.execute(
                        select(Milestone.order)
                        .where(Milestone.goal_id == goal_id)
                        .order_by(Milestone.order.desc())
                        .limit(1)
                    )
                    max_order = result.scalar() or 0

                    # Parse due date
                    due_date = None
                    if tool_input.get("due_date"):
                        due_date = datetime.fromisoformat(tool_input["due_date"])

                    # Create new milestone
                    order = tool_input.get("order", 0)
                    if order == 0:
                        order = max_order + 1

                    new_milestone = Milestone(
                        goal_id=goal_id,
                        title=tool_input["title"],
                        description=tool_input.get("description", ""),
                        due_date=due_date,
                        status=MilestoneStatus.PENDING,
                        order=order
                    )
                    db.add(new_milestone)
                    await db.commit()
                    await db.refresh(new_milestone)

                    # Create calendar event if user has Google Calendar connected
                    calendar_msg = ""
                    if user_refresh_token and user_calendar_id and due_date:
                        try:
                            calendar_service = CalendarService()
                            event = await calendar_service.create_milestone_event(
                                refresh_token=user_refresh_token,
                                calendar_id=user_calendar_id,
                                title=new_milestone.title,
                                description=new_milestone.description or "",
                                due_date=due_date,
                                goal_title=goal_title
                            )
                            new_milestone.calendar_event_id = event.id
                            await db.commit()
                            calendar_msg = " (added to Google Calendar)"
                        except Exception as cal_error:
                            print(f"Error creating calendar event: {cal_error}")

                    return ToolResult(
                        tool_use_id="",
                        content=f"Added milestone '{new_milestone.title}' with ID {new_milestone.id}{calendar_msg}"
                    )

            elif tool_name == "update_milestone":
                milestone_id = tool_input["milestone_id"]
                async with AsyncSessionLocal() as db:
                    result = await db.execute(
                        select(Milestone).where(Milestone.id == milestone_id)
                    )
                    milestone = result.scalar_one_or_none()

                    if not milestone:
                        return ToolResult(
                            tool_use_id="",
                            content=f"Milestone with ID {milestone_id} not found",
                            is_error=True
                        )

                    # Track calendar updates
                    calendar_updates = {}

                    # Update fields if provided
                    updates = []
                    if "title" in tool_input:
                        milestone.title = tool_input["title"]
                        calendar_updates["title"] = tool_input["title"]
                        updates.append(f"title to '{tool_input['title']}'")
                    if "description" in tool_input:
                        milestone.description = tool_input["description"]
                        calendar_updates["description"] = tool_input["description"]
                        updates.append("description")
                    if "due_date" in tool_input:
                        milestone.due_date = datetime.fromisoformat(tool_input["due_date"])
                        calendar_updates["due_date"] = tool_input["due_date"]
                        updates.append(f"due date to {tool_input['due_date']}")
                    if "status" in tool_input:
                        milestone.status = MilestoneStatus(tool_input["status"])
                        calendar_updates["status"] = tool_input["status"]
                        updates.append(f"status to {tool_input['status']}")

                    await db.commit()

                    # Update calendar event if it exists
                    calendar_msg = ""
                    if user_refresh_token and user_calendar_id and milestone.calendar_event_id and calendar_updates:
                        try:
                            calendar_service = CalendarService()
                            await calendar_service.update_milestone_event(
                                refresh_token=user_refresh_token,
                                calendar_id=user_calendar_id,
                                event_id=milestone.calendar_event_id,
                                updates=calendar_updates,
                                goal_title=goal_title
                            )
                            calendar_msg = " (calendar updated)"
                        except Exception as cal_error:
                            print(f"Error updating calendar event: {cal_error}")

                    return ToolResult(
                        tool_use_id="",
                        content=f"Updated milestone '{milestone.title}': changed {', '.join(updates)}{calendar_msg}"
                    )

            elif tool_name == "delete_milestone":
                milestone_id = tool_input["milestone_id"]
                async with AsyncSessionLocal() as db:
                    result = await db.execute(
                        select(Milestone).where(Milestone.id == milestone_id)
                    )
                    milestone = result.scalar_one_or_none()

                    if not milestone:
                        return ToolResult(
                            tool_use_id="",
                            content=f"Milestone with ID {milestone_id} not found",
                            is_error=True
                        )

                    title = milestone.title
                    calendar_event_id = milestone.calendar_event_id

                    await db.delete(milestone)
                    await db.commit()

                    # Delete calendar event if it exists
                    calendar_msg = ""
                    if user_refresh_token and user_calendar_id and calendar_event_id:
                        try:
                            calendar_service = CalendarService()
                            deleted = await calendar_service.delete_milestone_event(
                                refresh_token=user_refresh_token,
                                calendar_id=user_calendar_id,
                                event_id=calendar_event_id
                            )
                            if deleted:
                                calendar_msg = " (removed from calendar)"
                        except Exception as cal_error:
                            print(f"Error deleting calendar event: {cal_error}")

                    reason = tool_input.get("reason", "as requested")
                    return ToolResult(
                        tool_use_id="",
                        content=f"Deleted milestone '{title}' ({reason}){calendar_msg}"
                    )

            elif tool_name == "reorder_milestones":
                milestone_ids = tool_input["milestone_ids"]
                async with AsyncSessionLocal() as db:
                    for new_order, milestone_id in enumerate(milestone_ids, start=1):
                        result = await db.execute(
                            select(Milestone).where(Milestone.id == milestone_id)
                        )
                        milestone = result.scalar_one_or_none()
                        if milestone:
                            milestone.order = new_order
                    await db.commit()

                return ToolResult(
                    tool_use_id="",
                    content=f"Reordered {len(milestone_ids)} milestones"
                )

            else:
                return ToolResult(
                    tool_use_id="",
                    content=f"Unknown tool: {tool_name}",
                    is_error=True
                )

        except Exception as e:
            return ToolResult(
                tool_use_id="",
                content=f"Error executing {tool_name}: {str(e)}",
                is_error=True
            )

    return execute_tool


@app.websocket("/chat/{goal_id}")
async def websocket_chat(websocket: WebSocket, goal_id: int) -> None:
    """
    WebSocket endpoint for real-time AI chat about a goal.
    Uses Claude with tool-calling to provide coaching and milestone management.
    """
    await websocket.accept()
    claude_service = ClaudeService()
    chat_history: List[dict] = []

    try:
        # Load goal and milestones from database
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(Goal)
                .options(selectinload(Goal.milestones), selectinload(Goal.chat_messages), selectinload(Goal.user))
                .where(Goal.id == goal_id)
            )
            goal = result.scalar_one_or_none()

            if not goal:
                await websocket.send_json({
                    "type": "error",
                    "content": f"Goal {goal_id} not found"
                })
                await websocket.close()
                return

            goal_title = goal.title
            goal_description = goal.description or ""
            user_refresh_token = goal.user.google_refresh_token if goal.user else None
            user_calendar_id = goal.user.google_calendar_id if goal.user else None

            # Load existing chat history from DB
            for msg in goal.chat_messages:
                chat_history.append({
                    "role": msg.role.value,
                    "content": msg.content
                })

        # Get current milestones
        milestones_data = await get_milestones_for_goal(goal_id)

        # Create tool executor with calendar integration
        tool_executor = create_tool_executor(
            goal_id, websocket, user_refresh_token, user_calendar_id, goal_title
        )

        # Send welcome message
        welcome_msg = f"Hi! I'm here to help you with your goal: **{goal_title}**. "
        if milestones_data:
            pending = sum(1 for m in milestones_data if m["status"] == "pending")
            completed = sum(1 for m in milestones_data if m["status"] == "completed")
            welcome_msg += f"You have {len(milestones_data)} milestones ({completed} completed, {pending} pending). "
        welcome_msg += "\n\nI can help you:\n- Add new milestones\n- Update or mark milestones complete\n- Remove milestones that are no longer relevant\n- Discuss your progress\n\nHow can I help you today?"

        await websocket.send_json({
            "type": "message",
            "role": "assistant",
            "content": welcome_msg
        })

        while True:
            # Receive message from client
            data = await websocket.receive_text()
            message = json.loads(data)
            user_content = message.get("content", "")

            if not user_content.strip():
                continue

            # Save user message to DB
            async with AsyncSessionLocal() as db:
                user_msg = ChatMessage(
                    goal_id=goal_id,
                    role=ChatRole.USER,
                    content=user_content
                )
                db.add(user_msg)
                await db.commit()

            # Refresh milestones before each interaction
            milestones_data = await get_milestones_for_goal(goal_id)

            # Process with Claude using tools
            full_response = ""
            tool_actions = []

            async for event in claude_service.chat_with_tools(
                goal_id=goal_id,
                goal_title=goal_title,
                goal_description=goal_description,
                milestones=milestones_data,
                user_message=user_content,
                chat_history=chat_history,
                tool_executor=tool_executor
            ):
                event_type = event.get("type")

                if event_type == "text":
                    # Send text chunk to client
                    content = event.get("content", "")
                    full_response += content
                    await websocket.send_json({
                        "type": "chunk",
                        "content": content
                    })

                elif event_type == "tool_use":
                    # Notify client about tool being used
                    tool_name = event.get("name")
                    tool_input = event.get("input", {})
                    tool_actions.append({"tool": tool_name, "input": tool_input})
                    await websocket.send_json({
                        "type": "tool_use",
                        "name": tool_name,
                        "input": tool_input
                    })

                elif event_type == "tool_result":
                    # Notify client about tool result
                    await websocket.send_json({
                        "type": "tool_result",
                        "name": event.get("name"),
                        "result": event.get("result"),
                        "is_error": event.get("is_error", False)
                    })

                elif event_type == "done":
                    # Final message
                    pass

            # If milestones were modified, send updated list
            if tool_actions:
                updated_milestones = await get_milestones_for_goal(goal_id)
                await websocket.send_json({
                    "type": "milestones_updated",
                    "milestones": updated_milestones
                })

            # Send end of stream marker (NOT the full content again - that causes duplicates)
            # The frontend has already accumulated the chunks
            await websocket.send_json({
                "type": "stream_end",
                "role": "assistant"
            })

            # Update chat history for context
            chat_history.append({"role": "user", "content": user_content})
            chat_history.append({"role": "assistant", "content": full_response})

            # Save assistant response to DB
            async with AsyncSessionLocal() as db:
                assistant_msg = ChatMessage(
                    goal_id=goal_id,
                    role=ChatRole.ASSISTANT,
                    content=full_response
                )
                db.add(assistant_msg)
                await db.commit()

    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"WebSocket error: {e}")
        import traceback
        traceback.print_exc()
        try:
            await websocket.close(code=1011, reason=str(e)[:100])
        except:
            pass
