# Decisions

DevOps decisions for this repository, recorded when they are made. The application code belongs to the client and is not modified unless required.

## Repository and workflow (2026-10-24)

| Decision | Rejected | Reason |
|---|---|---|
| One GitLab repository per application (`olympic-tracker`, `workshop-api`) | monorepo | each app has its own versions, releases, registry and pipeline |
| GitLab is the source of truth; GitHub is a read-only push mirror | manual double push, CI on GitHub | a single CI, no manual sync |
| Work on a branch, merge into `main` through a merge request | commits on `main` | the pipeline is tested on a branch before merging |
| Repository docs in English (2026-10-28) | French | same language as the client's README |
| Public GitLab group and projects (2026-10-30) | private (initial choice, 2026-10-24) | recommended by the mentor; the code is already public on the GitHub mirror; Kubernetes pulls images without registry credentials. Consequence: pipeline logs are public, so secrets are masked and protected CI/CD variables, never printed |

## Containerization (2026-10-28)

| Decision | Rejected | Reason |
|---|---|---|
| Multi-stage `Dockerfile`: Node stage builds, nginx stage serves | single stage | Node and `node_modules` are only needed to build; the final image only holds nginx and static files (~76 MB) |
| Build image `node:24-alpine` | Node 20.11 (README), Node 20, Node 22 | Angular 20 requires Node 20.19+; Node 20 is end-of-life since April 2026; Node 24 is the latest LTS and the version tested locally |
| Runtime image `nginx:1.27-alpine` | `nginx:latest`, Debian-based image | version tested by the README; fixed minor version for reproducible builds; Alpine is smaller |
| Floating tags (`24-alpine`, `1.27-alpine`) | exact version or digest | security patches are picked up automatically; pinning can come with the release pipeline if needed |
| Client's `nginx/nginx.conf` used as is | custom config | it already serves `/app` with the `try_files` fallback a single-page app needs. **Port changed on 2026-10-30, see below** |
| Official nginx image (runs as root) | `nginx-unprivileged` (non-root) | simplest option that meets the requirement. Possible improvement: the client's config already puts the PID and temp files in `/tmp`, so switching to non-root is cheap. **Superseded on 2026-10-30, see below** |
| Tests not run in the image | `npm test` in the build stage | Karma needs Chrome, which the Alpine image lacks; tests get their own CI job |
| `.dockerignore` excludes generated files and files not needed to build | no `.dockerignore` | smaller build context; a macOS `node_modules` must never overwrite the Linux one; editing the README does not invalidate the build cache |
| Health check in Compose: `wget --spider http://127.0.0.1/` | no health check; `curl`; `localhost` | `docker compose ps` shows the real state of the app; `wget` ships with Alpine (BusyBox), `curl` does not; on Alpine `localhost` may resolve to `::1` while nginx only listens on IPv4. **Port 8080 since 2026-10-30** |
| Karma JUnit reports (`reports/`) ignored by git | committing them | generated output; the CI will publish them as artifacts |

## Non-root container (2026-10-30)

| Decision | Rejected | Reason |
|---|---|---|
| Runtime image `nginxinc/nginx-unprivileged:1.27-alpine` (user `nginx`, uid 101) | official `nginx` image as root; official image + `USER nginx` | a compromised nginx no longer runs as root; same as the back-end image; image maintained by the nginx team for this purpose; same nginx version, so only one thing changes |
| nginx listens on 8080 (client's `nginx/nginx.conf` edited: `listen 80` → `listen 8080`) | keep 80 | a non-root process cannot bind a port below 1024 in Kubernetes. One-line change in the client's config, which already puts the PID and temp files in `/tmp` |
| Host port unchanged: Compose publishes `80:8080` | `8080:8080` | the application stays at http://localhost |
| Done before the first release | after the CI pipeline | the container port is part of the image contract: changing it after a release would be a breaking change |

## Test script (2026-10-30)

| Decision | Rejected | Reason |
|---|---|---|
| Bash script `scripts/run-tests.sh` | Python | the script only chains commands; Bash is in every Debian-based CI image, Python is not guaranteed. Consequence: the CI image must provide Bash (not the case of Alpine images by default) |
| Same file in both repositories, project type detected from marker files (`package.json` + `angular.json`, or `gradlew`) | one script per repository; shared `ci-templates` project | one behaviour for both apps, and each repository stays self-contained. A shared project remains possible (question for the mentor) |
| Reports collected into `test-results/` | changing the output folder in `karma.conf.js` | client configuration untouched; the CI only needs one report path for both apps |
| Reports collected even when tests fail; the run fails if no report is found | stop at the first failure | GitLab needs the report to show which test failed; a run without a report means no test was checked |
| Exit code of the test tool passed through; `2` when the tests could not run | always `1` | tells "the code is broken" from "the environment is broken"; keeps tool-specific codes (e.g. 137 = killed, out of memory) |
| `npm ci` when `node_modules` is missing | `npm install` | installs the exact versions of `package-lock.json`, as the README recommends for CI |
| `test-results/` ignored by git | — | generated output, published by the CI |
