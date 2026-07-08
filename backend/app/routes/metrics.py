from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.database import get_db
from app.models.schemas import Goal, Metric, MetricEntry, User
from app.services.auth0 import get_current_user
from app.services.claude_service import ClaudeService

router = APIRouter(tags=["metrics"])


# ---------- Pydantic models ----------

class MetricEntryResponse(BaseModel):
    id: int
    amount: int
    note: str
    logged_at: datetime

    class Config:
        from_attributes = True


class MetricEntryCreate(BaseModel):
    amount: int = Field(1, ge=1, le=100000)
    note: str = ""
    logged_at: Optional[datetime] = None


class MetricCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    unit: str = ""
    symbol: str = "chart.bar.fill"
    color: str = "#1E9068"
    target: Optional[int] = Field(None, ge=1)
    order: int = 0


class MetricUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    unit: Optional[str] = None
    symbol: Optional[str] = None
    color: Optional[str] = None
    target: Optional[int] = None
    order: Optional[int] = None


class SuggestMetricsRequest(BaseModel):
    transcript: str = Field(..., min_length=1, max_length=8000)


class ProposedMetric(BaseModel):
    name: str
    unit: str = ""
    symbol: str = "chart.bar.fill"
    color: str = "#1E9068"
    target: Optional[int] = None


class SuggestMetricsResponse(BaseModel):
    metrics: List[ProposedMetric] = []


class MetricResponse(BaseModel):
    id: int
    goal_id: int
    name: str
    unit: str
    symbol: str
    color: str
    target: Optional[int] = None
    order: int
    created_at: datetime
    entries: List[MetricEntryResponse] = []
    total: int = 0

    class Config:
        from_attributes = True


# ---------- Helpers ----------

async def _owned_goal(goal_id: int, db: AsyncSession, user: User) -> Goal:
    result = await db.execute(
        select(Goal).where(Goal.id == goal_id, Goal.user_id == user.id)
    )
    goal = result.scalar_one_or_none()
    if not goal:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=f"Goal {goal_id} not found")
    return goal


async def _owned_metric(metric_id: int, db: AsyncSession, user: User) -> Metric:
    result = await db.execute(
        select(Metric)
        .options(selectinload(Metric.entries), selectinload(Metric.goal))
        .where(Metric.id == metric_id)
    )
    metric = result.scalar_one_or_none()
    if not metric or metric.goal.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=f"Metric {metric_id} not found")
    return metric


def _to_response(metric: Metric) -> MetricResponse:
    return MetricResponse(
        id=metric.id,
        goal_id=metric.goal_id,
        name=metric.name,
        unit=metric.unit,
        symbol=metric.symbol,
        color=metric.color,
        target=metric.target,
        order=metric.order,
        created_at=metric.created_at,
        entries=[MetricEntryResponse.model_validate(e) for e in metric.entries],
        total=sum(e.amount for e in metric.entries),
    )


# ---------- Routes ----------

@router.get("/goals/{goal_id}/metrics", response_model=List[MetricResponse])
async def list_metrics(
    goal_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[MetricResponse]:
    await _owned_goal(goal_id, db, current_user)
    result = await db.execute(
        select(Metric)
        .options(selectinload(Metric.entries))
        .where(Metric.goal_id == goal_id)
        .order_by(Metric.order, Metric.id)
    )
    return [_to_response(m) for m in result.scalars().all()]


@router.post("/goals/{goal_id}/suggest-metrics", response_model=SuggestMetricsResponse)
async def suggest_metrics(
    goal_id: int,
    data: SuggestMetricsRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SuggestMetricsResponse:
    """Given a spoken description, have Claude propose custom metrics.
    Does not persist — the client confirms, then POSTs the ones it wants.
    """
    goal = await _owned_goal(goal_id, db, current_user)
    try:
        raw = await ClaudeService().suggest_metrics(
            goal_title=goal.title, identity=goal.identity, transcript=data.transcript)
    except Exception as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, detail=f"Suggestion failed: {exc}")
    return SuggestMetricsResponse(metrics=[ProposedMetric(**m) for m in raw])


@router.post("/goals/{goal_id}/metrics", response_model=MetricResponse,
             status_code=status.HTTP_201_CREATED)
async def create_metric(
    goal_id: int,
    data: MetricCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> MetricResponse:
    await _owned_goal(goal_id, db, current_user)
    metric = Metric(
        goal_id=goal_id,
        name=data.name,
        unit=data.unit,
        symbol=data.symbol,
        color=data.color,
        target=data.target,
        order=data.order,
    )
    db.add(metric)
    await db.commit()
    await db.refresh(metric, attribute_names=["entries"])
    return _to_response(metric)


@router.put("/metrics/{metric_id}", response_model=MetricResponse)
async def update_metric(
    metric_id: int,
    data: MetricUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> MetricResponse:
    metric = await _owned_metric(metric_id, db, current_user)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(metric, field, value)
    await db.commit()
    await db.refresh(metric, attribute_names=["entries"])
    return _to_response(metric)


@router.delete("/metrics/{metric_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_metric(
    metric_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    metric = await _owned_metric(metric_id, db, current_user)
    await db.delete(metric)
    await db.commit()


@router.post("/metrics/{metric_id}/entries", response_model=MetricResponse,
             status_code=status.HTTP_201_CREATED)
async def log_entry(
    metric_id: int,
    data: MetricEntryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> MetricResponse:
    metric = await _owned_metric(metric_id, db, current_user)
    entry = MetricEntry(metric_id=metric.id, amount=data.amount, note=data.note)
    if data.logged_at:
        entry.logged_at = data.logged_at
    db.add(entry)
    await db.commit()
    await db.refresh(metric, attribute_names=["entries"])
    return _to_response(metric)


@router.delete("/metrics/{metric_id}/entries/{entry_id}",
               status_code=status.HTTP_204_NO_CONTENT)
async def delete_entry(
    metric_id: int,
    entry_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    metric = await _owned_metric(metric_id, db, current_user)
    entry = next((e for e in metric.entries if e.id == entry_id), None)
    if not entry:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=f"Entry {entry_id} not found")
    await db.delete(entry)
    await db.commit()
