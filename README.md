# GoalCraft

AI-powered goal planning and accountability platform that helps users set, track, and achieve their goals through intelligent coaching and regular check-ins.

## Tech Stack

### Backend
- **Framework**: FastAPI (Python 3.11+)
- **Database**: PostgreSQL (Neon in production, local Postgres for development)
- **AI**: Anthropic Claude for goal coaching and planning
- **SMS**: Twilio for check-in notifications
- **Deployment**: Google Cloud Run
- **Scheduler**: Google Cloud Scheduler for periodic check-ins

### Frontend
- **Framework**: Flutter Web
- **Deployment**: GitHub Pages — live at https://harrolee.github.io/goalcraft/

### iOS App ("Screen Test")
- **Framework**: Native SwiftUI (iOS 17+), a custom-metrics dashboard for identity-based goals
- **Location**: `GoalCraftiOS/` (project generated from `project.yml` via XcodeGen)
- See `GoalCraftiOS/APP_STORE.md` for submission metadata and status

### Infrastructure
- **CI/CD**: GitHub Actions
- **Container Registry**: Google Container Registry
- **Secrets**: Google Secret Manager

## Local Development Setup

### Prerequisites
- Docker and Docker Compose
- Python 3.11+
- Flutter SDK 3.0+
- Google Cloud SDK (for deployment)

### Backend Setup

1. Clone the repository:
```bash
git clone https://github.com/your-org/goalcraft.git
cd goalcraft
```

2. Create a `.env` file in the `backend` directory:
```bash
cp backend/.env.example backend/.env
# Edit backend/.env with your local configuration
```

3. Start the local development environment:
```bash
docker-compose up -d
```

4. The backend API will be available at `http://localhost:8000`
5. API documentation is available at `http://localhost:8000/docs`

### Frontend Setup

1. Navigate to the frontend directory:
```bash
cd frontend
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the development server:
```bash
flutter run -d chrome
```

## Environment Variables

### Backend Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `DATABASE_URL` | PostgreSQL connection string (Neon in prod) | Yes |
| `ANTHROPIC_API_KEY` | Anthropic Claude API key for AI coaching | Yes |
| `AUTH0_DOMAIN` | Auth0 tenant domain (API auth) | Yes (prod) |
| `AUTH0_AUDIENCE` | Auth0 API audience | Optional |
| `DEV_AUTH_BYPASS` | Local dev only: skip Auth0 and use a fixed dev user. **Must be false in production.** | No |
| `TWILIO_ACCOUNT_SID` | Twilio account SID | Yes |
| `TWILIO_AUTH_TOKEN` | Twilio auth token | Yes |
| `TWILIO_PHONE_NUMBER` | Twilio phone number for SMS | Yes |
| `JWT_SECRET_KEY` | Secret key for JWT tokens | Yes |
| `GCP_PROJECT_ID` | Google Cloud project ID | Yes (prod) |
| `ENVIRONMENT` | Environment name (development/production) | Yes |

### Frontend Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `API_BASE_URL` | Backend API URL | Yes |
| `AUTH0_DOMAIN` | Auth0 tenant domain | Yes (Auth) |
| `AUTH0_CLIENT_ID` | Auth0 client ID | Yes (Auth) |
| `AUTH0_AUDIENCE` | Auth0 API audience | Yes (Auth) |
| `AUTH0_REDIRECT_URI` | Auth0 redirect URI | Optional |

## Deployment

### Backend Deployment (Google Cloud Run)

#### Prerequisites
1. Google Cloud project with billing enabled
2. Enable required APIs:
```bash
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  cloudscheduler.googleapis.com
```

3. Create secrets in Secret Manager:
```bash
echo -n "your-database-url" | gcloud secrets create DATABASE_URL --data-file=-
echo -n "your-openai-key" | gcloud secrets create OPENAI_API_KEY --data-file=-
echo -n "your-twilio-sid" | gcloud secrets create TWILIO_ACCOUNT_SID --data-file=-
echo -n "your-twilio-token" | gcloud secrets create TWILIO_AUTH_TOKEN --data-file=-
echo -n "your-twilio-number" | gcloud secrets create TWILIO_PHONE_NUMBER --data-file=-
echo -n "your-jwt-secret" | gcloud secrets create JWT_SECRET_KEY --data-file=-
```

#### Manual Deployment
```bash
cd backend
gcloud builds submit --config=cloudbuild.yaml
```

#### Automated Deployment
Push to the `main` branch with changes in `backend/**` to trigger automatic deployment via GitHub Actions.

### Frontend Deployment (GitHub Pages)

The Flutter web app deploys to **GitHub Pages** at https://harrolee.github.io/goalcraft/
(served under the `/goalcraft/` base path).

#### Automated Deployment
Push to the `main` branch with changes in `frontend/**` to trigger the
`.github/workflows/frontend.yml` workflow, which builds Flutter web and publishes to
GitHub Pages. It can also be run manually via **Actions → Deploy Frontend → Run workflow**.

Static legal/support pages live in `frontend/web/{privacy,terms,about,support}/` and are
published by the same build (available at `/goalcraft/privacy/`, etc.).

> Note: an earlier revision of this README described Cloudflare Pages; the project now
> deploys to GitHub Pages. `frontend/build_web.sh` still contains a legacy Cloudflare hint.

### Setting Up Cloud Scheduler

After deploying the backend, set up the Cloud Scheduler for periodic check-ins:

```bash
cd backend
python scripts/setup_scheduler.py
```

This creates an hourly job that triggers the check-in endpoint.

## API Endpoints

### Authentication
- `POST /auth/register` - Register new user
- `POST /auth/login` - User login
- `POST /auth/refresh` - Refresh JWT token

### Goals
- `GET /goals` - List user's goals
- `POST /goals` - Create new goal
- `GET /goals/{id}` - Get goal details
- `PUT /goals/{id}` - Update goal
- `DELETE /goals/{id}` - Delete goal

### Milestones
- `GET /goals/{goal_id}/milestones` - List milestones for a goal
- `POST /goals/{goal_id}/milestones` - Create milestone
- `PUT /milestones/{id}` - Update milestone
- `DELETE /milestones/{id}` - Delete milestone

### Metrics (custom, user-defined measurements per goal)
- `GET /goals/{goal_id}/metrics` - List a goal's metrics (with entries and totals)
- `POST /goals/{goal_id}/metrics` - Create a metric
- `PUT /metrics/{id}` - Update a metric
- `DELETE /metrics/{id}` - Delete a metric
- `POST /metrics/{id}/entries` - Log an entry (increment)
- `DELETE /metrics/{id}/entries/{entry_id}` - Delete an entry

### Account
- `GET /account/me` - Current user profile
- `DELETE /account` - Permanently delete the account and all associated data (cascade)

### Chat (AI Coaching)
- `POST /chat` - Send message to AI coach
- `GET /chat/history` - Get chat history

### Check-ins
- `POST /check-ins/trigger` - Trigger check-in processing (Cloud Scheduler)
- `GET /check-ins/webhook` - Twilio webhook for SMS responses

## Database Schema

See `schema.sql` for the complete database schema. The main tables are:
- `users` - User accounts and profiles
- `goals` - User goals (with identity framing) and AI-generated plans
- `milestones` - Goal milestones and progress tracking
- `metrics` - Custom, user-defined measurements attached to a goal
- `metric_entries` - Individual logged entries that increment a metric
- `chat_messages` - AI coaching conversation history
- `check_ins` - Scheduled check-ins and responses

## Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Submit a pull request
4. Ensure CI checks pass

## License

MIT License - see LICENSE file for details.
