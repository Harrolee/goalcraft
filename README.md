# GoalCraft

AI-powered goal planning and accountability platform that helps users set, track, and achieve their goals through intelligent coaching and regular check-ins.

## Tech Stack

### Backend
- **Framework**: FastAPI (Python 3.11+)
- **Database**: PostgreSQL (Neon in production, local Postgres for development)
- **AI**: OpenAI GPT-4 for goal coaching and planning
- **SMS**: Twilio for check-in notifications
- **Deployment**: Google Cloud Run
- **Scheduler**: Google Cloud Scheduler for periodic check-ins

### Frontend
- **Framework**: Flutter Web
- **Deployment**: Cloudflare Pages

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
| `OPENAI_API_KEY` | OpenAI API key for AI coaching | Yes |
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

### Frontend Deployment (Cloudflare Pages)

#### Prerequisites
1. Cloudflare account with Pages enabled
2. Create a Cloudflare API token with Pages permissions

#### Manual Deployment
```bash
cd frontend
./build_web.sh
npx wrangler pages deploy build/web --project-name=goalcraft
```

#### Automated Deployment
Push to the `main` branch with changes in `frontend/**` to trigger automatic deployment via GitHub Actions.

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

### Chat (AI Coaching)
- `POST /chat` - Send message to AI coach
- `GET /chat/history` - Get chat history

### Check-ins
- `POST /check-ins/trigger` - Trigger check-in processing (Cloud Scheduler)
- `GET /check-ins/webhook` - Twilio webhook for SMS responses

## Database Schema

See `schema.sql` for the complete database schema. The main tables are:
- `users` - User accounts and profiles
- `goals` - User goals with AI-generated plans
- `milestones` - Goal milestones and progress tracking
- `chat_messages` - AI coaching conversation history
- `check_ins` - Scheduled check-ins and responses

## Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Submit a pull request
4. Ensure CI checks pass

## License

MIT License - see LICENSE file for details.
