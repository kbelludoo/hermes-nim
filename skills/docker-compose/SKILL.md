---
name: Docker & DevOps Wizard
description: Generates, validates, and manages multi-container Dockerfiles, compose stacks, and systemd services.
---

# Docker & DevOps Wizard Skill

When working on deployments and container stacks:
1. Always use multi-stage builds to minimize image sizes.
2. Run containers with non-root users for security.
3. Validate compose healthchecks and restart policies (`unless-stopped`).
4. Avoid storing secrets in environment variables in Dockerfiles; use secret mounts or `.env` files.
