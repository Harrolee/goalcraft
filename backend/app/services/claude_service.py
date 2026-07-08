import json
from datetime import datetime
from typing import AsyncGenerator, List, Optional, Any, Dict, Callable, Awaitable
from dataclasses import dataclass

import anthropic
from anthropic import AsyncAnthropic

from app.config import get_settings


@dataclass
class MilestoneData:
    """Data class for milestone information."""
    title: str
    description: str
    due_date: str
    order: int


@dataclass
class ToolResult:
    """Result from executing a tool."""
    tool_use_id: str
    content: str
    is_error: bool = False


# Tool schema for milestone extraction (used during goal creation)
MILESTONE_EXTRACTION_TOOL = {
    "name": "create_milestones",
    "description": "Create a structured list of milestones for achieving a goal. Each milestone should be a specific, actionable step with a clear due date.",
    "input_schema": {
        "type": "object",
        "properties": {
            "milestones": {
                "type": "array",
                "description": "List of milestones to achieve the goal",
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {
                            "type": "string",
                            "description": "Short, actionable title for the milestone"
                        },
                        "description": {
                            "type": "string",
                            "description": "Detailed description of what needs to be accomplished"
                        },
                        "due_date": {
                            "type": "string",
                            "description": "Due date in ISO 8601 format (YYYY-MM-DD)"
                        },
                        "order": {
                            "type": "integer",
                            "description": "Order of the milestone (1-based)"
                        }
                    },
                    "required": ["title", "description", "due_date", "order"]
                }
            }
        },
        "required": ["milestones"]
    }
}

# Tools for milestone management in chat
MILESTONE_MANAGEMENT_TOOLS = [
    {
        "name": "add_milestone",
        "description": "Add a new milestone to the goal. Use this when the user wants to add a new step or task to their goal plan.",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                    "description": "Short, actionable title for the milestone"
                },
                "description": {
                    "type": "string",
                    "description": "Detailed description of what needs to be accomplished"
                },
                "due_date": {
                    "type": "string",
                    "description": "Due date in ISO 8601 format (YYYY-MM-DD)"
                },
                "order": {
                    "type": "integer",
                    "description": "Order position for the milestone (1-based). Use 0 to add at the end."
                }
            },
            "required": ["title", "description", "due_date"]
        }
    },
    {
        "name": "update_milestone",
        "description": "Update an existing milestone. Use this when the user wants to change the title, description, due date, or status of a milestone.",
        "input_schema": {
            "type": "object",
            "properties": {
                "milestone_id": {
                    "type": "integer",
                    "description": "The ID of the milestone to update"
                },
                "title": {
                    "type": "string",
                    "description": "New title for the milestone (optional)"
                },
                "description": {
                    "type": "string",
                    "description": "New description for the milestone (optional)"
                },
                "due_date": {
                    "type": "string",
                    "description": "New due date in ISO 8601 format (YYYY-MM-DD) (optional)"
                },
                "status": {
                    "type": "string",
                    "enum": ["pending", "in_progress", "completed", "skipped"],
                    "description": "New status for the milestone (optional)"
                }
            },
            "required": ["milestone_id"]
        }
    },
    {
        "name": "delete_milestone",
        "description": "Delete a milestone from the goal. Use this when the user wants to remove a step that's no longer relevant.",
        "input_schema": {
            "type": "object",
            "properties": {
                "milestone_id": {
                    "type": "integer",
                    "description": "The ID of the milestone to delete"
                },
                "reason": {
                    "type": "string",
                    "description": "Brief reason for deleting (for confirmation message)"
                }
            },
            "required": ["milestone_id"]
        }
    },
    {
        "name": "reorder_milestones",
        "description": "Reorder the milestones. Use this when the user wants to change the sequence of their milestones.",
        "input_schema": {
            "type": "object",
            "properties": {
                "milestone_ids": {
                    "type": "array",
                    "items": {"type": "integer"},
                    "description": "List of milestone IDs in the desired order"
                }
            },
            "required": ["milestone_ids"]
        }
    },
    {
        "name": "get_milestones",
        "description": "Get the current list of milestones with their details. Use this to check the current state before making changes.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    }
]


# Type for tool executor functions
ToolExecutor = Callable[[str, Dict[str, Any]], Awaitable[ToolResult]]


class ClaudeService:
    """Service for interacting with Claude API for goal planning."""

    def __init__(self):
        settings = get_settings()
        self.client = AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
        self.model = "claude-sonnet-5"

    async def suggest_metrics(
        self,
        goal_title: str,
        identity: Optional[str],
        transcript: str,
    ) -> List[Dict[str, Any]]:
        """Propose custom metrics for a goal from a spoken description.

        Returns a list of dicts: name, unit, symbol (SF Symbol), color (hex),
        target (int). Nothing is persisted here.
        """
        symbols = [
            "sparkles", "pencil.and.scribble", "waveform", "person.2.fill",
            "dollarsign.circle.fill", "music.note", "mic.fill", "star.fill",
            "flame.fill", "book.fill", "paintbrush.fill", "figure.run",
            "checkmark.seal.fill", "calendar", "chart.line.uptrend.xyaxis",
        ]
        colors = ["#1E9068", "#116B4E", "#3AA981", "#C9A55C", "#E9D19A", "#C6413B"]

        tool = {
            "name": "propose_metrics",
            "description": "Propose the handful of trackable metrics that would prove someone is becoming the identity they described.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "metrics": {
                        "type": "array",
                        "description": "3–6 concrete, countable metrics",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string", "description": "Short metric name, e.g. 'Songs Released'"},
                                "unit": {"type": "string", "description": "Unit label, e.g. 'songs' (may be empty)"},
                                "symbol": {"type": "string", "enum": symbols, "description": "Best-fitting SF Symbol"},
                                "color": {"type": "string", "enum": colors, "description": "Accent color hex"},
                                "target": {"type": "integer", "description": "A meaningful target to chase (>=1)"},
                            },
                            "required": ["name", "unit", "symbol", "color", "target"],
                        },
                    }
                },
                "required": ["metrics"],
            },
        }

        system_prompt = (
            "You turn a person's spoken description of who they want to become into a small, "
            "concrete set of COUNTABLE metrics — the evidence that would prove the identity is real. "
            "Prefer things you tally over time (counts, sessions, releases). Avoid vague or mood-based "
            "measures. Pick 3–6. Choose the closest SF Symbol and an accent color from the allowed lists."
        )
        user_prompt = (
            f"Goal: {goal_title}\n"
            f"Identity: {identity or 'not specified'}\n"
            f"What they said:\n\"\"\"\n{transcript}\n\"\"\"\n\n"
            "Use the propose_metrics tool."
        )

        response = await self.client.messages.create(
            model=self.model,
            max_tokens=1024,
            system=system_prompt,
            tools=[tool],
            tool_choice={"type": "tool", "name": "propose_metrics"},
            messages=[{"role": "user", "content": user_prompt}],
        )
        for block in response.content:
            if getattr(block, "type", None) == "tool_use" and block.name == "propose_metrics":
                return block.input.get("metrics", [])
        return []

    async def plan_goal(
        self,
        goal_description: str,
        target_date: Optional[datetime] = None
    ) -> List[MilestoneData]:
        """
        Generate a structured plan with milestones for achieving a goal.

        Args:
            goal_description: Description of the goal to plan
            target_date: Optional target date for completing the goal

        Returns:
            List of MilestoneData objects representing the plan
        """
        target_date_str = target_date.strftime("%Y-%m-%d") if target_date else "not specified"
        today = datetime.now().strftime("%Y-%m-%d")

        system_prompt = """You are an expert goal planning assistant. Your role is to help users break down their goals into actionable, time-bound milestones.

When creating milestones:
- Make each milestone specific and measurable
- Ensure milestones are achievable within their timeframes
- Order milestones logically (dependencies first)
- Space milestones appropriately between now and the target date
- Include both preparation and execution milestones
- Be realistic about time requirements"""

        user_prompt = f"""Please create a detailed plan with milestones for the following goal:

Goal: {goal_description}
Target completion date: {target_date_str}
Today's date: {today}

Break this goal down into 4-8 specific, actionable milestones. Each milestone should have:
- A clear, concise title
- A detailed description of what needs to be done
- A realistic due date between now and the target date

Use the create_milestones tool to provide your response."""

        response = await self.client.messages.create(
            model=self.model,
            max_tokens=2048,
            system=system_prompt,
            tools=[MILESTONE_EXTRACTION_TOOL],
            tool_choice={"type": "tool", "name": "create_milestones"},
            messages=[{"role": "user", "content": user_prompt}]
        )

        # Extract milestones from tool use response
        milestones = []
        for content_block in response.content:
            if content_block.type == "tool_use" and content_block.name == "create_milestones":
                tool_input = content_block.input
                for milestone_data in tool_input.get("milestones", []):
                    milestones.append(MilestoneData(
                        title=milestone_data["title"],
                        description=milestone_data["description"],
                        due_date=milestone_data["due_date"],
                        order=milestone_data["order"]
                    ))

        return milestones

    async def plan_goal_streaming(
        self,
        goal_description: str,
        target_date: Optional[datetime] = None
    ) -> AsyncGenerator[str, None]:
        """
        Generate a plan with streaming response for real-time updates.

        Args:
            goal_description: Description of the goal to plan
            target_date: Optional target date for completing the goal

        Yields:
            String chunks of the response as they arrive
        """
        target_date_str = target_date.strftime("%Y-%m-%d") if target_date else "not specified"
        today = datetime.now().strftime("%Y-%m-%d")

        system_prompt = """You are an expert goal planning assistant. Help users break down their goals into actionable milestones. Be encouraging and practical."""

        user_prompt = f"""Help me plan this goal: {goal_description}
Target date: {target_date_str}
Today: {today}

Provide a brief overview and then use the create_milestones tool to structure the plan."""

        async with self.client.messages.stream(
            model=self.model,
            max_tokens=2048,
            system=system_prompt,
            tools=[MILESTONE_EXTRACTION_TOOL],
            messages=[{"role": "user", "content": user_prompt}]
        ) as stream:
            async for text in stream.text_stream:
                yield text

    async def chat_about_goal(
        self,
        goal_description: str,
        milestones: List[dict],
        user_message: str,
        chat_history: List[dict]
    ) -> AsyncGenerator[str, None]:
        """
        Have a conversation about a goal and its progress (without tools).

        Args:
            goal_description: Description of the goal
            milestones: Current milestones for the goal
            user_message: User's message
            chat_history: Previous messages in the conversation

        Yields:
            String chunks of the response
        """
        system_prompt = f"""You are a supportive goal coaching assistant. You're helping the user work towards their goal.

Goal: {goal_description}

Current milestones:
{json.dumps(milestones, indent=2)}

Be encouraging, ask clarifying questions when needed, and help the user stay on track. If they're struggling, offer practical suggestions."""

        messages = chat_history + [{"role": "user", "content": user_message}]

        async with self.client.messages.stream(
            model=self.model,
            max_tokens=1024,
            system=system_prompt,
            messages=messages
        ) as stream:
            async for text in stream.text_stream:
                yield text

    async def chat_with_tools(
        self,
        goal_id: int,
        goal_title: str,
        goal_description: str,
        milestones: List[dict],
        user_message: str,
        chat_history: List[dict],
        tool_executor: ToolExecutor
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        Have a conversation with tool-calling capabilities for milestone management.

        Args:
            goal_id: ID of the goal
            goal_title: Title of the goal
            goal_description: Description of the goal
            milestones: Current milestones for the goal
            user_message: User's message
            chat_history: Previous messages in the conversation
            tool_executor: Async function to execute tools

        Yields:
            Dict with type and content:
            - {"type": "text", "content": "..."} for text chunks
            - {"type": "tool_use", "name": "...", "input": {...}} for tool calls
            - {"type": "tool_result", "name": "...", "result": "..."} for tool results
            - {"type": "done", "content": "..."} for final response
        """
        today = datetime.now().strftime("%Y-%m-%d")

        milestones_info = "\n".join([
            f"  - ID {m['id']}: \"{m['title']}\" (status: {m['status']}, due: {m.get('due_date', 'no date')}, order: {m.get('order', 0)})"
            for m in milestones
        ]) if milestones else "  No milestones yet."

        system_prompt = f"""You are a supportive goal coaching assistant with the ability to manage milestones. You're helping the user work towards their goal.

Goal: {goal_title}
Description: {goal_description or 'No description provided'}
Today's date: {today}

Current milestones:
{milestones_info}

You have tools to:
- Add new milestones (add_milestone)
- Update existing milestones (update_milestone) - can change title, description, due date, or status
- Delete milestones (delete_milestone)
- Reorder milestones (reorder_milestones)
- Get current milestones (get_milestones)

Guidelines:
- Be encouraging and supportive
- When the user asks to add, change, or remove milestones, use the appropriate tool
- When marking milestones complete or changing status, use update_milestone with the status field
- Always confirm what you did after using a tool
- If the user's request is ambiguous, ask for clarification
- Reference milestones by their ID when using tools
- Keep responses concise but helpful"""

        messages = chat_history + [{"role": "user", "content": user_message}]

        # Initial API call with tools
        response = await self.client.messages.create(
            model=self.model,
            max_tokens=1024,
            system=system_prompt,
            tools=MILESTONE_MANAGEMENT_TOOLS,
            messages=messages
        )

        # Process response in an agentic loop
        while True:
            # Collect text and tool uses from response
            text_content = ""
            tool_uses = []

            for block in response.content:
                if block.type == "text":
                    text_content += block.text
                elif block.type == "tool_use":
                    tool_uses.append(block)

            # Yield any text content
            if text_content:
                yield {"type": "text", "content": text_content}

            # If no tool uses or stop reason is end_turn, we're done
            if not tool_uses or response.stop_reason == "end_turn":
                yield {"type": "done", "content": text_content}
                break

            # Execute tools and collect results
            tool_results = []
            for tool_use in tool_uses:
                yield {
                    "type": "tool_use",
                    "name": tool_use.name,
                    "input": tool_use.input,
                    "id": tool_use.id
                }

                # Execute the tool
                result = await tool_executor(tool_use.name, tool_use.input)

                yield {
                    "type": "tool_result",
                    "name": tool_use.name,
                    "result": result.content,
                    "is_error": result.is_error
                }

                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_use.id,
                    "content": result.content,
                    "is_error": result.is_error
                })

            # Continue conversation with tool results
            messages = messages + [
                {"role": "assistant", "content": response.content},
                {"role": "user", "content": tool_results}
            ]

            response = await self.client.messages.create(
                model=self.model,
                max_tokens=1024,
                system=system_prompt,
                tools=MILESTONE_MANAGEMENT_TOOLS,
                messages=messages
            )
