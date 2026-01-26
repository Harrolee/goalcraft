from app.routes.goals import router as goals_router
from app.routes.milestones import router as milestones_router
from app.routes.auth import router as auth_router
from app.routes.checkins import router as checkins_router
from app.routes.vapi_webhook import router as vapi_webhook_router

__all__ = ["goals_router", "milestones_router", "auth_router", "checkins_router", "vapi_webhook_router"]
