# Decisions

DevOps decisions for this repository, recorded when they are made. The application code belongs to the client and is not modified unless required.

## Repository and workflow (2026-10-24)

| Decision | Rejected | Reason |
|---|---|---|
| One GitLab repository per application (`olympic-tracker`, `workshop-api`) | monorepo | each app has its own versions, releases, registry and pipeline |
| GitLab is the source of truth; GitHub is a read-only push mirror | manual double push, CI on GitHub | a single CI, no manual sync |
| Work on a branch, merge into `main` through a merge request | commits on `main` | the pipeline is tested on a branch before merging |
| Repository docs in English (2026-10-28) | French | same language as the client's README |

## Containerization (2026-10-28)

| Decision | Rejected | Reason |
|---|---|---|
| Multi-stage `Dockerfile`: Node stage builds, nginx stage serves | single stage | Node and `node_modules` are only needed to build; the final image only holds nginx and static files (~76 MB) |
| Build image `node:24-alpine` | Node 20.11 (README), Node 20, Node 22 | Angular 20 requires Node 20.19+; Node 20 is end-of-life since April 2026; Node 24 is the latest LTS and the version tested locally |
| Runtime image `nginx:1.27-alpine` | `nginx:latest`, Debian-based image | version tested by the README; fixed minor version for reproducible builds; Alpine is smaller |
| Floating tags (`24-alpine`, `1.27-alpine`) | exact version or digest | security patches are picked up automatically; pinning can come with the release pipeline if needed |
| Client's `nginx/nginx.conf` used as is | custom config | it already serves `/app` with the `try_files` fallback a single-page app needs |
| Official nginx image (runs as root) | `nginx-unprivileged` (non-root) | simplest option that meets the requirement. Possible improvement: the client's config already puts the PID and temp files in `/tmp`, so switching to non-root is cheap |
| Tests not run in the image | `npm test` in the build stage | Karma needs Chrome, which the Alpine image lacks; tests get their own CI job |
| `.dockerignore` excludes generated files and files not needed to build | no `.dockerignore` | smaller build context; a macOS `node_modules` must never overwrite the Linux one; editing the README does not invalidate the build cache |
| Health check in Compose: `wget --spider http://127.0.0.1/` | no health check; `curl`; `localhost` | `docker compose ps` shows the real state of the app; `wget` ships with Alpine (BusyBox), `curl` does not; on Alpine `localhost` may resolve to `::1` while nginx only listens on IPv4 |
| Karma JUnit reports (`reports/`) ignored by git | committing them | generated output; the CI will publish them as artifacts |
