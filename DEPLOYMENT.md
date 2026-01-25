# GoalCraft Deployment Guide

This guide walks you through deploying GoalCraft to production using Google Cloud Run (backend) and Cloudflare Pages (frontend).

## Prerequisites

- GitHub account
- Google Cloud Platform account with billing enabled
- Cloudflare account
- Google Cloud CLI (`gcloud`) installed locally

## Step 1: Create GitHub Repository

```bash
# From the goalcraft directory
git add -A
git commit -m "Initial commit"

# Create repo on GitHub, then:
git remote add origin https://github.com/YOUR_USERNAME/goalcraft.git
git push -u origin main
```

## Step 2: Set Up Google Cloud Platform

### 2.1 Create Project & Enable APIs

```bash
# Set your project ID
export PROJECT_ID="goalcraft-prod"

# Create project (or use existing)
gcloud projects create $PROJECT_ID --name="GoalCraft"
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  containerregistry.googleapis.com
```

### 2.2 Set Up Workload Identity Federation (for GitHub Actions)

```bash
# Create workload identity pool
gcloud iam workload-identity-pools create "github-pool" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create provider for GitHub
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Create service account for deployment
gcloud iam service-accounts create "github-actions" \
  --display-name="GitHub Actions Deploy"

# Grant necessary permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Allow GitHub Actions to impersonate the service account
# Replace YOUR_GITHUB_USERNAME/goalcraft with your actual repo
gcloud iam service-accounts add-iam-policy-binding \
  "github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_GITHUB_USERNAME/goalcraft"
```

### 2.3 Create Secrets in Secret Manager

```bash
# Database URL (use Neon, Supabase, or Cloud SQL)
echo -n "postgresql://user:password@host:5432/goalcraft" | \
  gcloud secrets create DATABASE_URL --data-file=-

# Anthropic API Key
echo -n "sk-ant-..." | \
  gcloud secrets create ANTHROPIC_API_KEY --data-file=-

# Google OAuth credentials (from Google Cloud Console)
echo -n "your-client-id.apps.googleusercontent.com" | \
  gcloud secrets create GOOGLE_CLIENT_ID --data-file=-

echo -n "your-client-secret" | \
  gcloud secrets create GOOGLE_CLIENT_SECRET --data-file=-
```

### 2.4 Get Values for GitHub Secrets

```bash
# Get Workload Identity Provider
gcloud iam workload-identity-pools providers describe "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --format="value(name)"
# Output: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider

# Service account email
echo "github-actions@$PROJECT_ID.iam.gserviceaccount.com"
```

## Step 3: Set Up Cloudflare Pages

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Navigate to **Workers & Pages** → **Create**
3. Select **Pages** → **Connect to Git**
4. Skip connecting to Git (we'll deploy via API)
5. Create a project named `goalcraft`

### Get Cloudflare Credentials

1. Go to **My Profile** → **API Tokens**
2. Create a token with **Cloudflare Pages:Edit** permission
3. Note your **Account ID** from the dashboard URL

## Step 4: Configure GitHub Secrets

Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions**

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `GCP_PROJECT_ID` | Your GCP project ID (e.g., `goalcraft-prod`) |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full provider path from step 2.4 |
| `GCP_SERVICE_ACCOUNT` | `github-actions@PROJECT_ID.iam.gserviceaccount.com` |
| `CLOUDFLARE_API_TOKEN` | Your Cloudflare API token |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account ID |
| `API_BASE_URL` | Will be set after first backend deploy |

## Step 5: Set Up Google OAuth for Calendar

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to **APIs & Services** → **Credentials**
3. Create **OAuth 2.0 Client ID** (Web application)
4. Add authorized redirect URIs:
   - `https://goalcraft.pages.dev/auth/google/callback` (production)
   - `http://localhost:3001/auth/google/callback` (development)
5. Save the Client ID and Secret to GCP Secret Manager (step 2.3)

### Google OAuth Verification (for public use)

For other users to connect their calendars, you need to verify your OAuth app:

1. Go to **APIs & Services** → **OAuth consent screen**
2. Fill out the app information
3. Add scopes: `https://www.googleapis.com/auth/calendar`
4. Submit for verification (takes 2-6 weeks for review)

**For testing with up to 100 users before verification:**
- Add test users in the OAuth consent screen
- Users must be added before they can authorize

## Step 6: Deploy

### Initial Backend Deploy

Push to main branch to trigger deployment:

```bash
git push origin main
```

After the backend deploys, get the Cloud Run URL:

```bash
gcloud run services describe goalcraft-backend \
  --region us-central1 \
  --format 'value(status.url)'
# Output: https://goalcraft-backend-xxxxx-uc.a.run.app
```

### Update Frontend API URL

Add the `API_BASE_URL` secret to GitHub:
- Value: `https://goalcraft-backend-xxxxx-uc.a.run.app/api`

Then trigger frontend deploy:

```bash
# Make a small change or use workflow_dispatch
git commit --allow-empty -m "Trigger frontend deploy"
git push
```

## Step 7: Set Up Database

### Option A: Neon (Recommended - Serverless PostgreSQL)

1. Create account at [neon.tech](https://neon.tech)
2. Create a new project
3. Get the connection string
4. Update the `DATABASE_URL` secret in GCP Secret Manager

### Option B: Supabase

1. Create project at [supabase.com](https://supabase.com)
2. Get the connection string from **Settings** → **Database**
3. Update the `DATABASE_URL` secret

### Initialize Schema

Connect to your database and run `schema.sql`:

```bash
psql "your-database-url" -f schema.sql
```

## Monitoring & Logs

### Backend Logs

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=goalcraft-backend" --limit 50
```

### Health Check

```bash
curl https://goalcraft-backend-xxxxx-uc.a.run.app/health
```

## Troubleshooting

### Backend won't start
- Check Cloud Run logs for errors
- Verify all secrets are set in Secret Manager
- Ensure database is accessible

### OAuth errors
- Verify redirect URIs match exactly
- Check GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are correct
- For "redirect_uri_mismatch": add the exact URI to Google Console

### Frontend can't reach backend
- Check CORS settings in backend
- Verify API_BASE_URL includes `/api` suffix
- Check browser console for errors

## Production Checklist

- [ ] Database backups configured
- [ ] Cloud Run scaling limits set appropriately
- [ ] Error monitoring (Sentry/Cloud Error Reporting) set up
- [ ] Custom domain configured (optional)
- [ ] SSL certificates valid
- [ ] OAuth consent screen submitted for verification
- [ ] Rate limiting configured
