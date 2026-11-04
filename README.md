# Olympic Participation Tracker

## Context

The **Olympic Participation Tracker** is an application designed to record and analyze countries' participation in the Olympic Games. It provides statistics on medals obtained by each country, helping users gain insights into historical performance. Although the application is currently in its early development stages, we aim to create a robust and user-friendly tool for Olympic enthusiasts.

## Technical Context

The application is built using **Angular 20** and relies on **npm** for package management. Angular offers a powerful framework for creating dynamic web applications, and npm simplifies the process of managing dependencies and scripts.

Summary:

- **NodeJS**: Tested with version 24 (Angular 20 requires Node 20.19+, 22.12+ or 24)
- **NPM**: Tested with version 11
- **NGINX**: Tested with version 1.27

## Getting Started

### Install dependencies

Run `npm i` in local development to install NodeJS dependencies. If you are installing the app on a CI environment prefer to use `npm ci`. you can also change npm cache directory to your working directory as following

```bash
npm ci --cache .npm --prefer-offline
```

## Development server

Run `ng serve` for a dev server. Navigate to `http://localhost:4200/`. The application will automatically reload if you change any of the source files.

### Build

Run `npm run build` to build the project. The build artifacts will be stored in the `dist/olympic-games-starter/browser/` directory.

### Test

To run tests and ensure the application's functionality, use the following command:

```bash
npm test
```

Our test suite covers critical components, ensuring stability and reliability.

#### Unified test script

`scripts/run-tests.sh` runs the tests the same way locally and in CI. The same script is used in [workshop-api](https://gitlab.com/younesyousfipro-group/workshop-api): it detects the project type, then here installs the dependencies if `node_modules` is missing (`npm ci`), runs `npm test` and copies the JUnit XML report into `test-results/`.

```bash
./scripts/run-tests.sh
```

| Exit code | Meaning |
|---|---|
| `0` | tests passed |
| other, usually `1` (passed through from npm) | tests failed, the report is in `test-results/` |
| `2` | tests could not run: missing tool, failed install or no report produced |

Requires Bash, Node, npm and Chrome (Karma runs Chrome headless).

### Packaging

To package the application for distribution, run:

```bash
npm pack
```

This will create a distributable package containing the compiled code and necessary assets.

### Deploy on nginx

To deploy application on nginx web server with docker you can use nginx config located in the `nginx` folder. This one configure the root application folder in the `/app` folder.

After building the app copy the `dist/olympic-games-starter/browser` folder to the root application folder in the docker image.

## Run with Docker

The `Dockerfile` does both steps above in a multi-stage build: a `node:24-alpine` stage runs `npm ci` and `npm run build`, then a `nginxinc/nginx-unprivileged:1.27-alpine` stage (nginx running as a non-root user) only receives the nginx config and the built files. Tests are not run in the image (they need Chrome, see [Test](#test)).

With Docker Compose (recommended):

```bash
docker compose up -d --build   # build the image and start the container
docker compose ps              # wait for "(healthy)"
```

The application is available at http://localhost. Stop it with `docker compose down`.

With plain Docker:

```bash
docker build -t olympic-tracker:local .
docker run --rm -d -p 80:8080 --name olympic-tracker olympic-tracker:local
docker stop olympic-tracker
```

| | |
|---|---|
| Port | nginx listens on 8080 in the container, published on 80 on the host (change the host side in `docker-compose.yml`, e.g. `"8081:8080"`, if 80 is taken) |
| User | `nginx` (uid 101), not root: limits the impact if nginx is compromised. Check with `docker compose exec olympic-tracker id` |
| Environment variables | none: data comes from `src/assets/mock/olympic.json`, bundled at build time |
| Health check | `GET /` from inside the container, every 10 s |
| Image size | ~76 MB (nginx + static files, no Node) |

Design choices are recorded in [docs/decisions.md](docs/decisions.md).

### Publishing to GitLab Registry

To publish the application to a GitLab registry, follow these steps:

1. **Change Application Scope**:
   - Change the application scope for your new gitlab group. For example, if your repository url is `https://gitlab.com/your-gitlab-group-slug/olympic-games-starter` change the application name to `@your-gitlab-group-slug/olympic-games-starter`
   ```json
   {
      "name": "@your-gitlab-group-slug/olympic-games-starter",
      ...
   }
   ```
2. To publish, you need to create a file named `.npmrc` with the following content :

   ```ini
   @your-gitlab-group-slug:registry=https://gitlab.com/api/v4/projects/${GITLAB_PROJECT_ID}/packages/npm/
   //gitlab.com/api/v4/projects/${GITLAB_PROJECT_ID}/packages/npm/:_authToken="${GITLAB_TOKEN}"
   ```

3. **Set Environment Variables**:
   - Ensure that the following environment variables are specified:
     - `GITLAB_PROJECT_ID`: The ID of your GitLab project.
     - `GITLAB_TOKEN`: Your GitLab deploy token.
4. **Execute the Publish Command**:
   ```bash
   npm publish
   ```
   This will publish the package to your GitLab registry.

## CI/CD pipeline

[`.gitlab-ci.yml`](.gitlab-ci.yml) runs on every branch push and on every tag (branch and tag pipelines only, so a merge request shows the status of its branch pipeline without running a second one). The same file is used in [workshop-api](https://gitlab.com/younesyousfipro-group/workshop-api): each job only runs in the repository whose project type it matches.

| Stage | What it does |
|---|---|
| `test` | runs [`scripts/run-tests.sh`](scripts/run-tests.sh) in the job image; the JUnit report is shown in the pipeline's *Tests* tab, even when tests fail |
| `build` | once tests pass, builds the `Dockerfile` with Docker-in-Docker and pushes the image to the GitLab Container Registry (see [Container images](#container-images)) |
| `release` | on `main` only, once the image is built: semantic-release computes the version, commits it, tags it and creates the GitLab release; the tag starts a pipeline that builds the versioned image (see [Releases and versioning](#releases-and-versioning)) |

Differences between the two projects:

| | olympic-tracker | workshop-api |
|---|---|---|
| Job (selected by) | `test:npm` (`angular.json` exists) | `test:gradle` (`gradlew` exists) |
| Job image | `node:24` + Chromium installed with `apt-get` (Karma runs Chrome headless) | `eclipse-temurin:21-jdk` |
| Cache | `.npm/`, keyed on `package-lock.json` | `.gradle/wrapper` and `.gradle/caches`, keyed on `build.gradle` and the wrapper properties |
| Tests | 5 (Jasmine/Karma) | 2 (JUnit, repositories mocked, no database) |
| Test job duration, empty cache | ~1.5 min | ~1.5 min |
| Build job | same `build` job; only the `Dockerfile` differs (Node build + nginx runtime) | same `build` job; only the `Dockerfile` differs (Gradle build + JRE runtime) |
| Pipeline duration (test + build) | ~2.5 min | ~4 min |

The build job needs no secret: it logs in to the registry with the credentials GitLab gives each job, which expire with it. The release job needs the `GITLAB_TOKEN` variable (see [One-time setup](#one-time-setup)). To reproduce the test job locally in the same image:

```bash
docker run --rm -v "$PWD":/src:ro node:24 bash -c '
  git config --global --add safe.directory "*"
  git clone -q /src /app && cd /app
  apt-get update -qq && apt-get install -y -qq --no-install-recommends chromium >/dev/null
  CHROME_BIN=/usr/bin/chromium ./scripts/run-tests.sh'
```

### Container images

The `build` job pushes the image to the project's Container Registry (*Deploy → Container registry*), `registry.gitlab.com/younesyousfipro-group/olympic-tracker`, with two tags:

| Tag | Example | Pipeline | Moves | Use |
|---|---|---|---|---|
| commit SHA (`$CI_COMMIT_SHORT_SHA`) | `:a1b2c3d4` | every pipeline | never | know exactly which code runs; roll back |
| branch slug (`$CI_COMMIT_REF_SLUG`) | `:main` | branch pipeline | to the latest build of the branch | get the latest build of a branch |
| version (git tag without its `v`) | `:0.1.4` | tag pipeline, after a release | never | deploy a released version |

The release commit (`chore: release X.Y.Z`) starts no `main` pipeline (excluded by `workflow:rules`), so `:main` stays on the image of the commit before it; the two only differ by the version number in the project files. The release commit itself is built by its tag pipeline.

Run the image of a branch locally (public project, no login needed):

```bash
docker run --rm -p 80:8080 registry.gitlab.com/younesyousfipro-group/olympic-tracker:main
```

The application is available at http://localhost.

**Cleanup.** A cleanup policy (*Settings → Packages and registries → Container registry → Cleanup policies*) runs every week: it keeps `:main`, every version tag and the 10 most recent tags (*Keep tags matching* `(?:main|\d+\.\d+\.\d+)`; GitLab anchors the pattern itself), and removes the other tags (commit SHAs, work branches) older than 30 days. Removing a SHA tag does not remove an image that still has its version tag; images left without any tag are deleted by GitLab after 24 hours. To remove an image by hand: *Deploy → Container Registry*, select all its tags (its commit SHA and its branch or version), *Delete selected*.

Images are built for `linux/amd64` (GitLab.com runners): on an Apple Silicon Mac, Docker Desktop runs them with emulation and prints a "platform does not match" warning.

The pipeline publishes a container image, not the npm package described in [Publishing to GitLab Registry](#publishing-to-gitlab-registry).

Design choices are recorded in [docs/decisions.md](docs/decisions.md).

## Releases and versioning

Versions are not chosen by hand: **semantic-release** computes them from the commit messages, then publishes the release. The setup is the same in [workshop-api](https://gitlab.com/younesyousfipro-group/workshop-api).

### What semantic-release is

Two specifications and one tool:

| | What it is | Role here |
|---|---|---|
| [Semantic Versioning](https://semver.org) | a specification: `MAJOR.MINOR.PATCH` and what each number means | the version format |
| [Conventional Commits](https://www.conventionalcommits.org) | a specification: commit messages start with a type (`feat:`, `fix:`…) | the input semantic-release reads |
| [semantic-release](https://github.com/semantic-release/semantic-release) | an open-source Node.js command-line tool, extended by plugins | reads the commits since the last version, computes the next one, writes the changelog, tags and publishes |

It only reads commit messages, never the code. It is written in JavaScript, so its CI job uses a `node` image, but it works on any git repository: it versions the Java API the same way as the Angular front.

### Which commit gives which version

| Commit type | Example | Version change |
|---|---|---|
| `feat` | `feat: add medal chart` | minor: 0.1.3 → 0.2.0 |
| `fix`, `perf` | `fix: handle empty country list` | patch: 0.1.3 → 0.1.4 |
| `build` (project rule) | `build: upgrade nginx base image` | patch: the delivered image changes |
| `!` after the type, or a `BREAKING CHANGE:` footer | `feat!: rename API field` | major: 0.1.3 → 1.0.0 |
| `ci`, `docs`, `test`, `chore`, `refactor` | `docs: update README` | none |

How the next version is computed:

- Only the commits merged into `main` since the last version tag count; pushing to another branch never releases.
- The highest change wins, and the numbers on its right go back to zero: from 0.1.4, a `feat` gives 0.2.0, not 0.2.4.
- One merge request gives one release, whatever its number of commits: `fix` + `build` + `feat` + `docs` → 0.2.0, with the first three in the notes.
- A merge with only `docs`, `ci`, `test`, `chore` or `refactor` commits still runs the pipeline (tests, `:<sha>` and `:main` images) but publishes no version. A documentation-only push can skip the pipeline with `git push -o ci.skip`.
- A message that does not follow the convention is ignored without any error, so a fix written as `fixed the bug` is never released. Commits are written without a scope.

For example, from 0.1.4: an nginx or base image upgrade (`build:`) or a bug fix (`fix:`) gives 0.1.5; a new feature (`feat:`) gives 0.2.0.

### What happens on `main`

```
merge into main ─► pipeline "main": test → build (:<sha>, :main) → release
                                                                    │
  semantic-release:                                                 │
    1. finds the last version tag (e.g. v0.1.3)                     │
    2. reads the commits since that tag, computes the next version  │
    3. writes CHANGELOG.md and the version in the project files     │
    4. commits them to main ("chore: release X.Y.Z")                │
    5. tags that commit vX.Y.Z and creates the GitLab release ◄─────┘
                                                                    │
  the pushed tag starts a pipeline "vX.Y.Z": test → build (:<sha>, :X.Y.Z)
```

- No releasable commit since the last tag: the job ends green without releasing.
- `workflow:rules` keeps the release commit (title starting with `chore: release `) from starting a `main` pipeline: no loop, and the commit is built once, by its tag pipeline. `[skip ci]` in the message is not an option: GitLab reads it in the message of the commit, so it would also skip the tag pipeline (it did on the first releases, see [docs/decisions.md](docs/decisions.md)).
- The image tagged `:X.Y.Z` is built from the release commit, so the version in its files matches its tag.
- After a release, `main` on GitLab has one more commit than a local clone: pull before starting a new branch.

Results: *Deploy → Releases* (notes per version), *Code → Tags*, [`CHANGELOG.md`](CHANGELOG.md) (created by the first release), and the version tag in the Container Registry.

### Configuration files

[`.releaserc.json`](.releaserc.json) sets the release branch (`main`) and the plugins. Within a step, plugins run in the order of the file:

| Step | Plugin | What it does |
|---|---|---|
| analyze | `@semantic-release/commit-analyzer` | commit types → version change; `conventionalcommits` preset, plus `build` → patch |
| notes | `@semantic-release/release-notes-generator` | release notes; only the types that trigger a version are listed (Features, Bug Fixes, Performance Improvements, Build System) |
| prepare | `@semantic-release/changelog` | adds the notes to `CHANGELOG.md` |
| prepare | `@semantic-release/exec` | runs [`scripts/set-version.sh`](scripts/set-version.sh) `X.Y.Z` |
| prepare | `@semantic-release/git` | commits `CHANGELOG.md`, the version files and the chart's `Chart.yaml` (missing files are skipped, so the list covers both repositories) |
| publish | `@semantic-release/gitlab` | creates the GitLab release; comments on the merge requests it includes, opens an issue if the release fails |

`scripts/set-version.sh X.Y.Z` writes the version into the project file and into the `appVersion` of `helm/*/Chart.yaml` (the chart's default image tag). It detects the project type like `run-tests.sh` and fails (exit code 2) if a file does not show the new version afterwards. It does not depend on semantic-release and can be run by hand.

The plugin versions are pinned in the release job (`npm install -g` in a `node:24` image), not in `package.json`: semantic-release is a CI tool here, not a dependency of the application. The job clones the full history (`GIT_DEPTH: 0`): with GitLab's default shallow clone (20 commits), the last version tag can be missing and semantic-release would release `1.0.0`.

Differences between the two projects:

| | olympic-tracker | workshop-api |
|---|---|---|
| Version written in | `package.json` and `package-lock.json` | `build.gradle` (`version = '…'`) |
| How `set-version.sh` writes it | `npm version X.Y.Z --no-git-tag-version` | `sed` on the `version = '…'` line |
| Starting tag (client's last commit) | `v0.1.3` on `e2a98be` | `v0.2.4` on `7d12cbe` |
| First release | 0.1.4 | 0.2.5 |

### One-time setup

Already done for this project; listed to reproduce it or renew the token.

1. **Token.** *Edit profile → Personal access tokens*: a **legacy** personal access token with the `api` and `write_repository` scopes, expiring within a year. Project and group access tokens would be narrower but need a Premium subscription on GitLab.com; fine-grained tokens are not documented by the semantic-release GitLab plugin.
2. **CI/CD variable.** *Settings → CI/CD → Variables*: key `GITLAB_TOKEN` (the exact name the plugin reads), the token as value, **Masked** (job logs are public) and **Protected** (only pipelines on protected branches get it).
3. **Protected `main`.** *Settings → Repository → Protected branches*: the release job only receives the protected variable on a protected branch.
4. **Starting tag.** Without a tag, the first release would be `1.0.0`. The version delivered by the client is tagged on its last commit, so the first release continues from it:
   ```bash
   git tag -a v0.1.3 e2a98be -m "Version delivered by the client"
   git push origin v0.1.3
   ```
   That commit has no `.gitlab-ci.yml`, so the tag starts no pipeline.

When the token expires, the release job fails with an authentication error: create a new token and update the variable.

### Check a release without publishing it

A dry run reads the commits, computes the next version, checks the token and the push rights, and prints the release notes. It writes, commits, tags and publishes nothing. Run it from the repository, on a branch that exists on GitLab and is up to date.

Load the token first, on its own (type the command, press Enter, paste the token, press Enter; nothing is echoed). Do not paste it in one block with the next command: `read` would take the next pasted line as the token.

```bash
read -rs GITLAB_TOKEN && export GITLAB_TOKEN
echo ${#GITLAB_TOKEN}   # length of the token, not 0
```

Then:

```bash
npx -y \
  -p semantic-release@25.0.9 \
  -p @semantic-release/commit-analyzer@13.0.1 \
  -p @semantic-release/release-notes-generator@14.1.1 \
  -p @semantic-release/changelog@7.0.0 \
  -p @semantic-release/exec@7.1.0 \
  -p @semantic-release/git@11.0.1 \
  -p @semantic-release/gitlab@13.3.3 \
  -p conventional-changelog-conventionalcommits@9.3.1 \
  semantic-release --dry-run --no-ci --branches "$(git branch --show-current)"
unset GITLAB_TOKEN
```

`npx -p` installs the packages in npm's cache, not in the project. `--branches` replaces `main` for this run only. The preset stays on major version 9: version 10 needs `conventional-changelog-writer` 9, while the latest `@semantic-release/release-notes-generator` (14.1.1) still ships writer 8 and fails with *Missing helper: … requires conventional-changelog-writer@9*.

### Why the version is committed

semantic-release recommends keeping the version in git tags only and not committing during a release. The instructions of this project require the version to be synchronized in the project files, so the version files and `CHANGELOG.md` are committed by `@semantic-release/git`. The cost: a token allowed to push to `main`, a `workflow:rules` exception for the release commit, and a pull after each release. See [docs/decisions.md](docs/decisions.md).

## Deploy with Helm (Minikube)

The chart [`helm/olympic-tracker-chart/`](helm/olympic-tracker-chart/) deploys the released image from the registry: a Deployment (1 Pod) and a `LoadBalancer` Service. Tested with Helm 4.3, Minikube 1.35 (Kubernetes 1.32, Docker driver) on an Apple Silicon Mac: the `linux/amd64` image runs with Docker Desktop's emulation.

| File | Content |
|---|---|
| `Chart.yaml` | chart name, chart `version` (bumped by hand when the chart changes), `appVersion` (the default image tag, written by `set-version.sh` at each release) |
| `values.yaml` | default values, all under `app:` |
| `templates/` | `deployment.yaml`, `service.yaml` |

Values:

| Key | Default | Used for |
|---|---|---|
| `app.replicas` | `1` | Deployment `replicas` |
| `app.image` | `registry.gitlab.com/younesyousfipro-group/olympic-tracker` | image name, without tag |
| `app.tag` | `""` | image tag; empty = `appVersion` from `Chart.yaml` |
| `app.port` | `8080` | `containerPort`, readiness probe and Service `targetPort` (nginx runs as non-root) |
| `app.imagePullSecret` | `olympic-tracker-registry` | pull secret name; empty = no `imagePullSecrets` |
| `app.resources` | requests `50m` / `32Mi`, limits `200m` / `64Mi` | container `resources` |

Fixed in the templates: Service `port` 80 and type `LoadBalancer`; readiness probe `GET /`. Object names and the `app` label come from the release name (`<release>-deployment`, `<release>-service`), so two releases do not select each other's Pods. No environment variables, no volumes.

Differences between the two projects:

| | olympic-tracker | workshop-api |
|---|---|---|
| Kubernetes objects | 2: Deployment + `LoadBalancer` Service | 6: Secret, PVC, Deployment + headless Service (PostgreSQL), Deployment + `LoadBalancer` Service (API) |
| Images | `olympic-tracker` | `workshop-api` + `postgres:13` (Docker Hub, no pull secret) |
| Service → container port | 80 → 8080 | 8080 → 8080 |
| Configuration | none (static files, data inside the image) | database URL, username and password as environment variables |
| Secrets | pull secret only (created by hand) | pull secret (created by hand) + database Secret |
| Readiness probe | `GET /` | API: `GET /api/notions`; database: `pg_isready` |
| State | stateless: deleting the Pod loses nothing | PVC: data survives the Pod; `strategy: Recreate` |
| Start order | — | none: the API restarts until the database is ready |
| Uninstall | nothing lost | also deletes the PVC, so the data |

### 1. Registry credentials (once per cluster and namespace)

The project is public, so the image can be pulled anonymously; the chart still uses a pull secret, as a private registry would require.

1. On GitLab: *Settings → Repository → Deploy tokens → Add token*, scope **`read_registry`** only, with an expiration date. Keep the username and token (shown once) in a password manager.
2. Create the Secret (the token is typed without echo and stays out of the shell history):

   ```bash
   kubectl config current-context      # must be minikube
   read -rs TOKEN
   kubectl create secret docker-registry olympic-tracker-registry \
     --docker-server=registry.gitlab.com \
     --docker-username=<deploy token username> \
     --docker-password="$TOKEN"
   unset TOKEN
   ```

The kubelet (not the container) uses this Secret to pull the image. When the token expires, the Pod fails with `ErrImagePull`.

### 2. Check the chart

```bash
helm lint --strict helm/olympic-tracker-chart
helm template olympic-tracker helm/olympic-tracker-chart          # rendered YAML, no cluster needed
minikube start
helm install olympic-tracker helm/olympic-tracker-chart --dry-run=server   # validated by the API server, nothing created
```

`lint` checks the chart structure and the template syntax, not the Kubernetes fields: the server dry run does.

### 3. Install and check

```bash
helm install olympic-tracker helm/olympic-tracker-chart
helm list                              # olympic-tracker, deployed, app version 0.1.4
kubectl get pods                       # 1/1 Running
kubectl get endpointslices -l kubernetes.io/service-name=olympic-tracker-service   # the Pod IP, port 8080
```

Helm records each release revision in a Secret of the namespace (`sh.helm.release.v1.olympic-tracker.v1`).

### 4. Open the application

```bash
minikube service olympic-tracker-service --url
```

The command prints `http://127.0.0.1:<port>` and must stay open: with the Docker driver on macOS, the node IP is not reachable and this command holds a tunnel to the Service.

### 5. Remove

```bash
helm uninstall olympic-tracker
kubectl delete secret olympic-tracker-registry
```

### Troubleshooting

| Symptom | Likely cause | Look at |
|---|---|---|
| `helm install` fails: `cannot re-use a name that is still in use` | the release already exists | `helm list`; `helm uninstall olympic-tracker` first |
| `helm template` or `lint` fails | template syntax, indentation | the line given in the error |
| `ErrImagePull` / `ImagePullBackOff` | wrong image name or tag, Secret missing or token expired | `kubectl describe pod -l app=olympic-tracker` (Events) |
| `Running` but `0/1` | readiness probe failing | `kubectl describe pod`, `kubectl logs` |
| page does not load, Pod `1/1` | Service selector does not match the Pod labels (no endpoints) | `kubectl get endpointslices`, `kubectl get pods --show-labels` |

With a fixed tag the node keeps the image and does not pull it again, so the pull secret is not used. To test it, remove the image from the node first: `minikube image rm registry.gitlab.com/younesyousfipro-group/olympic-tracker:0.1.4`.

Design choices are recorded in [docs/decisions.md](docs/decisions.md#helm-chart-2026-11-04). The chart replaces the plain manifests of the `k8s/` folder (removed, see the decisions).
