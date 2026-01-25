#!/usr/bin/env python3
"""
Google Cloud Scheduler Setup Script for GoalCraft Check-ins

This script creates a Cloud Scheduler job that triggers the check-in endpoint
every hour to process due check-ins and send SMS notifications.

Usage:
    python setup_scheduler.py

Prerequisites:
    - Google Cloud SDK installed and authenticated
    - Cloud Scheduler API enabled
    - Cloud Run service deployed
    - Service account with Cloud Run Invoker role

Environment Variables:
    GCP_PROJECT_ID - Google Cloud project ID
    GCP_REGION - Google Cloud region (default: us-central1)
    CLOUD_RUN_SERVICE_NAME - Cloud Run service name (default: goalcraft-backend)
"""

import os
import sys
import subprocess
import json
from typing import Optional


def run_command(command: list[str], capture_output: bool = True) -> tuple[int, str, str]:
    """Run a shell command and return the result."""
    result = subprocess.run(
        command,
        capture_output=capture_output,
        text=True
    )
    return result.returncode, result.stdout, result.stderr


def get_project_id() -> str:
    """Get the GCP project ID from environment or gcloud config."""
    project_id = os.environ.get("GCP_PROJECT_ID")
    if project_id:
        return project_id

    returncode, stdout, _ = run_command(
        ["gcloud", "config", "get-value", "project"]
    )
    if returncode == 0 and stdout.strip():
        return stdout.strip()

    print("Error: Could not determine GCP project ID.")
    print("Set GCP_PROJECT_ID environment variable or run 'gcloud config set project <project-id>'")
    sys.exit(1)


def get_cloud_run_url(project_id: str, region: str, service_name: str) -> str:
    """Get the Cloud Run service URL."""
    returncode, stdout, stderr = run_command([
        "gcloud", "run", "services", "describe", service_name,
        "--region", region,
        "--project", project_id,
        "--format", "value(status.url)"
    ])

    if returncode != 0:
        print(f"Error getting Cloud Run service URL: {stderr}")
        print(f"Make sure the service '{service_name}' is deployed in region '{region}'")
        sys.exit(1)

    return stdout.strip()


def get_or_create_service_account(project_id: str, sa_name: str) -> str:
    """Get or create a service account for Cloud Scheduler."""
    sa_email = f"{sa_name}@{project_id}.iam.gserviceaccount.com"

    # Check if service account exists
    returncode, _, _ = run_command([
        "gcloud", "iam", "service-accounts", "describe", sa_email,
        "--project", project_id
    ])

    if returncode != 0:
        print(f"Creating service account: {sa_name}")
        returncode, _, stderr = run_command([
            "gcloud", "iam", "service-accounts", "create", sa_name,
            "--display-name", "GoalCraft Scheduler Service Account",
            "--project", project_id
        ])
        if returncode != 0:
            print(f"Error creating service account: {stderr}")
            sys.exit(1)

        # Grant Cloud Run Invoker role
        print("Granting Cloud Run Invoker role...")
        run_command([
            "gcloud", "projects", "add-iam-policy-binding", project_id,
            "--member", f"serviceAccount:{sa_email}",
            "--role", "roles/run.invoker"
        ])

    return sa_email


def create_scheduler_job(
    project_id: str,
    region: str,
    job_name: str,
    schedule: str,
    target_url: str,
    service_account_email: str,
    timezone: str = "UTC"
) -> None:
    """Create or update the Cloud Scheduler job."""

    # Check if job exists
    returncode, _, _ = run_command([
        "gcloud", "scheduler", "jobs", "describe", job_name,
        "--location", region,
        "--project", project_id
    ])

    if returncode == 0:
        print(f"Updating existing scheduler job: {job_name}")
        command = [
            "gcloud", "scheduler", "jobs", "update", "http", job_name,
            "--location", region,
            "--project", project_id,
            "--schedule", schedule,
            "--uri", target_url,
            "--http-method", "POST",
            "--oidc-service-account-email", service_account_email,
            "--time-zone", timezone,
            "--attempt-deadline", "180s",
            "--headers", "Content-Type=application/json"
        ]
    else:
        print(f"Creating new scheduler job: {job_name}")
        command = [
            "gcloud", "scheduler", "jobs", "create", "http", job_name,
            "--location", region,
            "--project", project_id,
            "--schedule", schedule,
            "--uri", target_url,
            "--http-method", "POST",
            "--oidc-service-account-email", service_account_email,
            "--time-zone", timezone,
            "--attempt-deadline", "180s",
            "--headers", "Content-Type=application/json"
        ]

    returncode, stdout, stderr = run_command(command)

    if returncode != 0:
        print(f"Error creating/updating scheduler job: {stderr}")
        sys.exit(1)

    print("Scheduler job configured successfully!")


def main():
    """Main function to set up Cloud Scheduler."""
    print("=" * 60)
    print("GoalCraft Cloud Scheduler Setup")
    print("=" * 60)

    # Configuration
    project_id = get_project_id()
    region = os.environ.get("GCP_REGION", "us-central1")
    service_name = os.environ.get("CLOUD_RUN_SERVICE_NAME", "goalcraft-backend")
    job_name = "goalcraft-checkins-trigger"
    sa_name = "goalcraft-scheduler"
    schedule = "0 * * * *"  # Every hour at minute 0
    timezone = "UTC"

    print(f"\nConfiguration:")
    print(f"  Project ID: {project_id}")
    print(f"  Region: {region}")
    print(f"  Service Name: {service_name}")
    print(f"  Job Name: {job_name}")
    print(f"  Schedule: {schedule} ({timezone})")
    print()

    # Get Cloud Run service URL
    print("Getting Cloud Run service URL...")
    service_url = get_cloud_run_url(project_id, region, service_name)
    target_url = f"{service_url}/check-ins/trigger"
    print(f"  Target URL: {target_url}")
    print()

    # Get or create service account
    print("Setting up service account...")
    sa_email = get_or_create_service_account(project_id, sa_name)
    print(f"  Service Account: {sa_email}")
    print()

    # Create scheduler job
    print("Configuring Cloud Scheduler job...")
    create_scheduler_job(
        project_id=project_id,
        region=region,
        job_name=job_name,
        schedule=schedule,
        target_url=target_url,
        service_account_email=sa_email,
        timezone=timezone
    )

    print()
    print("=" * 60)
    print("Setup Complete!")
    print("=" * 60)
    print()
    print("The scheduler will trigger check-ins every hour.")
    print()
    print("To manually trigger the job:")
    print(f"  gcloud scheduler jobs run {job_name} --location {region}")
    print()
    print("To view job status:")
    print(f"  gcloud scheduler jobs describe {job_name} --location {region}")
    print()
    print("To view job logs:")
    print(f"  gcloud logging read 'resource.type=cloud_scheduler_job AND resource.labels.job_id={job_name}'")


if __name__ == "__main__":
    main()
