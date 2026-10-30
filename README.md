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

[`.gitlab-ci.yml`](.gitlab-ci.yml) runs on every branch push (branch pipelines only, so a merge request shows the status of its branch pipeline without running a second one). The same file is used in [workshop-api](https://gitlab.com/younesyousfipro-group/workshop-api): each job only runs in the repository whose project type it matches.

| Stage | What it does |
|---|---|
| `test` | runs [`scripts/run-tests.sh`](scripts/run-tests.sh) in the job image; the JUnit report is shown in the pipeline's *Tests* tab, even when tests fail |

Differences between the two projects:

| | olympic-tracker | workshop-api |
|---|---|---|
| Job (selected by) | `test:npm` (`angular.json` exists) | `test:gradle` (`gradlew` exists) |
| Job image | `node:24` + Chromium installed with `apt-get` (Karma runs Chrome headless) | `eclipse-temurin:21-jdk` |
| Cache | `.npm/`, keyed on `package-lock.json` | `.gradle/wrapper` and `.gradle/caches`, keyed on `build.gradle` and the wrapper properties |
| Tests | 5 (Jasmine/Karma) | 2 (JUnit, repositories mocked, no database) |
| Duration, empty cache | ~1.5 min | ~1.5 min |

The test stage uses no secret. To reproduce the job locally in the same image:

```bash
docker run --rm -v "$PWD":/src:ro node:24 bash -c '
  git config --global --add safe.directory "*"
  git clone -q /src /app && cd /app
  apt-get update -qq && apt-get install -y -qq --no-install-recommends chromium >/dev/null
  CHROME_BIN=/usr/bin/chromium ./scripts/run-tests.sh'
```

Design choices are recorded in [docs/decisions.md](docs/decisions.md).
