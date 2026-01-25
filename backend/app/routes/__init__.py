from app.routes.goals import router as goals_router
from app.routes.milestones import router as milestones_router
from app.routes.auth import router as auth_router

__all__ = ["goals_router", "milestones_router", "auth_router"]
