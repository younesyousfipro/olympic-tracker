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

## CI pipeline: test stage (2026-10-30)

| Decision | Rejected | Reason |
|---|---|---|
| Same `.gitlab-ci.yml` copied in both repositories | shared `ci-templates` project with `include:` | same choice as the test script: each repository stays self-contained. Switching later only means moving the file and replacing it with an `include:` |
| One job per project type (`test:npm`, `test:gradle`) selected with `rules: exists` (`angular.json`, `gradlew`), sharing a hidden `.test` job | one job with an image variable set in each repository | the file stays identical and nothing is hidden in the GitLab settings. The CI detects the type itself because it must pick the job image before the script runs |
| Front image `node:24` + Chromium installed by `apt-get` | third-party Node + Chrome image | official images only; Debian-based, so Bash is available. Cost: about 30 to 60 s per run, to revisit if the CI quota gets tight |
| Back image `eclipse-temurin:21-jdk` | `gradle` image | same image as the Dockerfile build stage; JDK 21 avoids the Mockito failure seen under Java 25 |
| npm cache `.npm/` keyed on `package-lock.json`, set through `npm_config_*` variables | caching `node_modules/` | recommended by the client's README and GitLab; `node_modules` would be a very large archive. The test script is unchanged |
| Gradle cache `.gradle/wrapper` and `.gradle/caches` (`GRADLE_USER_HOME` in the project), keyed on `build.gradle` and the wrapper properties; Gradle daemon disabled | no cache | Gradle (~130 MB) and the dependencies are not downloaded on every run; a daemon is useless in a one-shot job |
| JUnit report published with `when: always` | report only on success | same logic as the script: the report is most useful when tests fail |
| Branch pipelines only (`workflow: rules: if: $CI_COMMIT_BRANCH`) | default rules | jobs with `rules:` would also run in merge request pipelines, so two pipelines per push (400 min/month quota). The merge request still shows the branch pipeline status. Tag pipelines will be decided with semantic-release |
| Only the `test` stage for now | declaring `build` and `release` in advance | each step adds its own stage |
| No secret used by the test stage | — | registry and release tokens come with the build and release stages |

## CI pipeline: build stage (2026-10-31)

| Decision | Rejected | Reason |
|---|---|---|
| One image, two tags: commit SHA (`:a1b2c3d4`, never moves) and branch name (`:main`, moves with each push) | branch in the image path (`<image>/main:a1b2c3d4`), the other reading of the instructions' example | the SHA tag tells exactly which code runs and allows a rollback; the branch tag gives the latest build of a branch. Same image name everywhere, so Helm only changes the tag |
| Branch name as a slug (`$CI_COMMIT_REF_SLUG`) | raw branch name | a `/` (`feature/x`) is not allowed in a Docker tag |
| Image built on every branch | `main` only | the pipeline is tested on a branch before merging. Cost: about 3 CI minutes more per push |
| Docker-in-Docker (`docker:29` job image + `docker:29-dind` service, TLS on) | Kaniko, Buildah; mounting the host Docker socket | listed in the instructions and documented by GitLab for its hosted runners; Kaniko is no longer maintained by Google; the host socket is not available on GitLab.com runners (and gives root on the host). Major version 29 = same as local Docker |
| Registry login with the job credentials (`$CI_REGISTRY_USER` / `$CI_REGISTRY_PASSWORD`, `--password-stdin`) | personal or project access token in a CI/CD variable | no secret to create or rotate; the credentials expire with the job; the password never appears in the public job log |

## CI pipeline: release stage (2026-11-01)

| Decision | Rejected | Reason |
|---|---|---|
| semantic-release runs **automatically on `main`**, after `build` | manual job; other branches | the merge request review is the human check, and the commit types already decide whether a version is due. No releasable commit = no release, the job stays green |
| Start from the client's version: tag **`v0.1.3`** set by hand on the client's last commit (`e2a98be`, version in `package.json` and `package-lock.json`: `0.1.3`) | first release `1.0.0` | keeps the client's version history; in SemVer, `1.0.0` means "stable API", a product decision for the client. The first release then lists exactly what the industrialization added |
| **`build` commits trigger a patch release**, on top of the defaults (`feat` minor, `fix`/`perf` patch) | defaults only | a `build` commit (Dockerfile, base image, dependencies) changes the delivered image, so it needs a new version. `ci`, `docs`, `test`, `chore` leave the image unchanged: no release |
| Versioned image **rebuilt in the tag pipeline** (`v1.2.3` tag → image `:1.2.3`) | retagging the image built earlier in the `main` pipeline | the version only exists after `build` has run on `main`; rebuilding from the release commit gives an image whose files carry the same version. Tests run again first. Cost: one extra pipeline per release |
| **Personal access token, legacy type** (`api` + `write_repository`) in a project CI/CD variable `GITLAB_TOKEN`, **masked and protected** | project or group access token; fine-grained personal access token; `CI_JOB_TOKEN`; dedicated bot account | project and group access tokens require Premium on GitLab.com; the job token cannot be relied on to push to `main` and trigger the tag pipeline; the permissions a fine-grained token needs are not documented by the semantic-release GitLab plugin, and a missing one would leave a pushed tag without its release; a bot account is overkill here. Masked: job logs are public. Protected: only `main` pipelines get it. Project level, not group level: the group hosts other projects. Expiry under one year (an expired token makes the release job fail visibly) |
| **Same `.releaserc.json` and `scripts/set-version.sh`** in both repositories; the script detects the project type and writes the version (`npm version --no-git-tag-version` or `build.gradle`) | `@semantic-release/npm` (front), a Gradle plugin (back) | same pattern as `run-tests.sh`: only the version file differs between the two applications. The npm plugin is meant to publish to the npm registry |
| **`CHANGELOG.md` committed** in addition to GitLab releases | GitLab releases only | the GitHub mirror copies branches and tags, not GitLab releases; the file is readable in any clone |
| Only the `version` line of the project files is changed (client code otherwise untouched) | — | required by the instructions: "synchronize the version in the project files" |
| Version files and `CHANGELOG.md` **committed during the release** (`@semantic-release/git`) | version kept in git tags only, injected into the image at build time (semantic-release's own recommendation) | the instructions require the version to be synchronized in the project files. Cost accepted: a token that pushes to `main`, a `workflow:rules` exception for the release commit, a pull after each release |
| **`conventionalcommits` preset** for analysis and notes | `angular` (default) | follows the specification used for the commits and lets the notes list a *Build System* section; with `angular`, a release triggered by `build` commits would have empty notes |
| Release notes list **only the types that trigger a version** (`feat`, `fix`, `perf`, `build`) | also `ci`, `docs`, `test`, `chore` | the notes describe what changes in the delivered image; the full history stays in git |
| Release commit **`chore: release X.Y.Z`** | default `chore(release): …` | no scope, like every commit of the repository; `chore` never triggers a version. `[skip ci]` dropped, see the next section |
| Configuration in **`.releaserc.json`** | `release.config.js`; `release` key in `package.json` | the API has no `package.json`; JSON runs no code; one file for both repositories |
| semantic-release and plugins **installed in the release job, versions pinned**, each published more than two weeks earlier | `devDependencies` of `package.json`; unpinned versions | no change to the client's dependencies, same setup for the Java API; a job that does not change keeps the same behaviour, and a freshly published (possibly compromised) package is not picked up |
| GitLab plugin with its defaults (comments on included merge requests, issue on failure) | disabling them | traceability at no cost; a failing release becomes visible |
| `conventionalcommits` preset pinned to **9.3.1** (latest of major 9) | 10.x (latest) | preset 10 requires `conventional-changelog-writer` 9, the latest `@semantic-release/release-notes-generator` (14.1.1) ships writer 8: the notes step fails (*Missing helper*). Found with a local dry run; to revisit when the notes generator moves to writer 9 |
| **Tag pipelines** accepted by `workflow:rules` (`$CI_COMMIT_TAG`), next to branch pipelines | a separate job triggered by the release job | a pushed tag starts a pipeline on its own; it runs the same `test` and `build` jobs, so every image in the registry has passed the tests |
| In a tag pipeline, `build` tags the image with the version (`v1.2.3` → `1.2.3`, plain `if` in the script) instead of the branch slug | keeping the `v`; `tagFormat: ${version}` without `v` | image tags are usually bare versions; the git tags keep the `v` format of semantic-release and of the starting tags already pushed |
| `:main` stays on the image of the commit before the release commit | building the release commit on `main` too | the release commit starts no `main` pipeline and only changes the version number; it is built by its tag pipeline (image `:X.Y.Z`) |
| `release` job: `node:24`, `npm install -g` of the pinned list, no cache | cache of the global npm folder | the job only runs on `main`; installing takes well under a minute |
| **`GIT_DEPTH: 0`** in the `release` job | default shallow clone (20 commits) | 21 commits separate `v0.1.3` from `main` in olympic-tracker: a shallow clone would miss the tag and semantic-release would release `1.0.0`. Not visible in a local dry run (full clone) |

## CI pipeline: release commit without `[skip ci]` (2026-11-01)

The first release (0.1.4) was published, but its tag pipeline was skipped and no `:0.1.4` image was built: GitLab reads `[skip ci]` in the message of the commit, and the version tag points to the release commit.

| Decision | Rejected | Reason |
|---|---|---|
| Release commit message without `[skip ci]`; the release commit is excluded from **branch** pipelines by `workflow:rules` (`$CI_COMMIT_BRANCH && $CI_COMMIT_TITLE =~ /^chore: release /` → `never`) | keeping `[skip ci]` | `[skip ci]` also skips the tag pipeline that builds the versioned image. In a tag pipeline `$CI_COMMIT_BRANCH` is empty, so the rule does not apply there |
| | dropping `[skip ci]` without a rule | the release commit would start a `main` pipeline too: two builds of the same commit at the same time, the SHA image tag overwritten, a few more CI minutes per release (no loop though: a `chore` commit never triggers a version) |
| Missing `:0.1.4` image built by a pipeline run by hand on the tag (*Build → Pipelines → New pipeline*) | retagging the image of the merge commit | that image was built before the version existed (its project files say the previous version); a manual pipeline is not skipped by `[skip ci]` |

