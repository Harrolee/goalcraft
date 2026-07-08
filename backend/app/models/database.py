from urllib.parse import urlparse, urlunparse, parse_qs, urlencode

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from typing import AsyncGenerator

from app.config import get_settings


class Base(DeclarativeBase):
    """Base class for all SQLAlchemy models."""
    pass


def get_async_database_url() -> str:
    """Convert standard postgres URL to asyncpg URL.

    Handles conversion of psycopg2-style parameters to asyncpg-compatible ones.
    Specifically converts sslmode=require to ssl=require for asyncpg.
    """
    url = get_settings().DATABASE_URL

    # Replace postgresql:// with postgresql+asyncpg://
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    elif url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+asyncpg://", 1)

    # Parse URL to handle query parameters
    parsed = urlparse(url)

    if parsed.query:
        # Parse query parameters
        params = parse_qs(parsed.query)

        # Convert sslmode to ssl for asyncpg
        if 'sslmode' in params:
            sslmode = params.pop('sslmode')[0]
            if sslmode in ('require', 'verify-ca', 'verify-full'):
                params['ssl'] = ['require']

        # Remove channel_binding as asyncpg handles this differently
        params.pop('channel_binding', None)

        # Rebuild query string (flatten single-item lists)
        new_query = urlencode({k: v[0] if len(v) == 1 else v for k, v in params.items()})

        # Reconstruct URL
        url = urlunparse((
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            parsed.params,
            new_query,
            parsed.fragment
        ))

    return url


# Create async engine
engine = create_async_engine(
    get_async_database_url(),
    echo=False,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
)

# Create async session factory
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency that provides an async database session."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db() -> None:
    """Initialize database tables and apply lightweight, idempotent migrations.

    `create_all` creates any missing tables (e.g. metrics, metric_entries) but does
    NOT add columns to tables that already exist. The ADD COLUMN IF NOT EXISTS
    statements below bring an older deployed schema up to date on boot without a
    separate migration tool. All statements are safe to run repeatedly.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

        migrations = [
            "ALTER TABLE goals ADD COLUMN IF NOT EXISTS identity TEXT",
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS auth0_id VARCHAR(255)",
            "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_auth0_id ON users (auth0_id)",
        ]
        for statement in migrations:
            try:
                await conn.exec_driver_sql(statement)
            except Exception as exc:  # never block startup on a best-effort migration
                print(f"init_db migration skipped ({statement}): {exc}")
