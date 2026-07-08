import enum
from datetime import datetime
from typing import Optional, List
from sqlalchemy import String, Text, ForeignKey, DateTime, Enum, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.database import Base


class MilestoneStatus(str, enum.Enum):
    """Status of a milestone."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    SKIPPED = "skipped"


class ChatRole(str, enum.Enum):
    """Role in a chat message."""
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"


class CheckInStatus(str, enum.Enum):
    """Status of a scheduled check-in."""
    PENDING = "pending"
    CALLING = "calling"
    COMPLETED = "completed"
    FAILED = "failed"


class User(Base):
    """User model for storing user information."""
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    auth0_id: Mapped[Optional[str]] = mapped_column(String(255), unique=True, nullable=True, index=True)
    google_refresh_token: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    google_calendar_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    phone_number: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    goals: Mapped[List["Goal"]] = relationship("Goal", back_populates="user", cascade="all, delete-orphan")

    def __repr__(self) -> str:
        return f"<User(id={self.id}, email={self.email})>"


class Goal(Base):
    """Goal model for storing user goals."""
    __tablename__ = "goals"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    # Identity-based framing: who the user is becoming (not an affirmation).
    identity: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    target_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="goals")
    milestones: Mapped[List["Milestone"]] = relationship(
        "Milestone", back_populates="goal", cascade="all, delete-orphan", order_by="Milestone.order"
    )
    metrics: Mapped[List["Metric"]] = relationship(
        "Metric", back_populates="goal", cascade="all, delete-orphan", order_by="Metric.order"
    )
    chat_messages: Mapped[List["ChatMessage"]] = relationship(
        "ChatMessage", back_populates="goal", cascade="all, delete-orphan", order_by="ChatMessage.created_at"
    )

    def __repr__(self) -> str:
        return f"<Goal(id={self.id}, title={self.title})>"


class Milestone(Base):
    """Milestone model for storing goal milestones."""
    __tablename__ = "milestones"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    goal_id: Mapped[int] = mapped_column(ForeignKey("goals.id", ondelete="CASCADE"), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    due_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[MilestoneStatus] = mapped_column(
        Enum(MilestoneStatus, values_callable=lambda x: [e.value for e in x], native_enum=False),
        default=MilestoneStatus.PENDING, nullable=False
    )
    order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    calendar_event_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    goal: Mapped["Goal"] = relationship("Goal", back_populates="milestones")
    check_ins: Mapped[List["CheckIn"]] = relationship(
        "CheckIn", back_populates="milestone", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Milestone(id={self.id}, title={self.title}, status={self.status})>"


class ChatMessage(Base):
    """ChatMessage model for storing conversation history."""
    __tablename__ = "chat_messages"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    goal_id: Mapped[int] = mapped_column(ForeignKey("goals.id", ondelete="CASCADE"), nullable=False, index=True)
    role: Mapped[ChatRole] = mapped_column(
        Enum(ChatRole, values_callable=lambda x: [e.value for e in x], native_enum=False), nullable=False
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    goal: Mapped["Goal"] = relationship("Goal", back_populates="chat_messages")

    def __repr__(self) -> str:
        return f"<ChatMessage(id={self.id}, role={self.role})>"


class CheckIn(Base):
    """CheckIn model for storing milestone check-ins via SMS."""
    __tablename__ = "check_ins"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    milestone_id: Mapped[int] = mapped_column(
        ForeignKey("milestones.id", ondelete="CASCADE"), nullable=False, index=True
    )
    status: Mapped[CheckInStatus] = mapped_column(
        Enum(CheckInStatus, values_callable=lambda x: [e.value for e in x], native_enum=False),
        default=CheckInStatus.PENDING,
        nullable=False,
    )
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    call_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    response: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    milestone: Mapped["Milestone"] = relationship("Milestone", back_populates="check_ins")

    def __repr__(self) -> str:
        return f"<CheckIn(id={self.id}, milestone_id={self.milestone_id})>"


class Metric(Base):
    """Custom, user-defined measurement attached to a goal.

    e.g. "Songs Released", "Cowriting Sessions Attended". Progress is the sum
    of its MetricEntry rows — nothing about the count is hardcoded.
    """
    __tablename__ = "metrics"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    goal_id: Mapped[int] = mapped_column(ForeignKey("goals.id", ondelete="CASCADE"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    unit: Mapped[str] = mapped_column(String(64), default="", nullable=False)
    symbol: Mapped[str] = mapped_column(String(64), default="chart.bar.fill", nullable=False)
    color: Mapped[str] = mapped_column(String(9), default="#1E9068", nullable=False)
    target: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    goal: Mapped["Goal"] = relationship("Goal", back_populates="metrics")
    entries: Mapped[List["MetricEntry"]] = relationship(
        "MetricEntry", back_populates="metric", cascade="all, delete-orphan",
        order_by="MetricEntry.logged_at"
    )

    def __repr__(self) -> str:
        return f"<Metric(id={self.id}, name={self.name})>"


class MetricEntry(Base):
    """A single logged event contributing to a metric (usually +1)."""
    __tablename__ = "metric_entries"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    metric_id: Mapped[int] = mapped_column(
        ForeignKey("metrics.id", ondelete="CASCADE"), nullable=False, index=True
    )
    amount: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    note: Mapped[str] = mapped_column(Text, default="", nullable=False)
    logged_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    metric: Mapped["Metric"] = relationship("Metric", back_populates="entries")

    def __repr__(self) -> str:
        return f"<MetricEntry(id={self.id}, metric_id={self.metric_id}, amount={self.amount})>"
