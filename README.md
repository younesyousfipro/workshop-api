# Workshop Organizer Web API

Welcome to the Workshop Organizer Web API! This application is designed to facilitate workshops open to the public. Whether you’re organizing coding bootcamps, art classes, or any other type of workshop, this API will help manage registrations, schedules, and resources.

## Table of Contents

1. Context
2. Technical Overview
3. Building and Running
4. Testing
5. Packaging
6. Publishing to GitLab Registry

## Context

Workshops play a crucial role in fostering learning and collaboration. Our application aims to streamline the workshop organization process, making it easier for organizers to manage participants, sessions, and materials. Whether you're a seasoned workshop host or just starting out, this API has got you covered!

## Technical Overview

- **Java Development Kit (JDK):** We use **JDK 21**, tested with **Adoptium**, to power our application.
- **Database:** Our backend relies on a **PostgreSQL 13** database for data storage.
- **Build Tool:** We leverage **Gradle 8.7** for managing dependencies and building the project.
- **Spring Boot:** Our application is based on **Spring Boot 3.2.4**, which provides a robust framework for creating RESTful APIs.
- **Application Server:** Our application can run on Tomcat server that require version 10.1.24.

## Building and Running

To compile and run the application locally, follow these steps:

1. Ensure you have JDK 21 installed.
2. Clone this repository.
3. Navigate to the project root directory.
4. Execute the following command to compile the Java code :
   ```bash
   ./gradlew clean compileJava
   ```
5. To run the application locally, either:
   Execute the main method in the Application class from your IDE.
   Use the Spring Boot Gradle Plugin :
   ```bash
   ./gradlew bootRun
   ```
   For production, package the application as WAR and use a tomcat server

To run the application with Docker, see [Run with Docker](#run-with-docker).

## Configuration

You can configure the application with these environment variables

- SPRING_DATASOURCE_URL: JDBC URI for DB access (ex. jdbc:postgresql://db:5432/mydatabase)
- SPRING_DATASOURCE_USERNAME: Database user name used by the application
- SPRING_DATASOURCE_PASSWORD: Database user password used by the application

## Testing

We take testing seriously! To verify the correctness of our application, run the following command:

```bash
./gradlew clean test
```

During execution junit reports are generated in the `build/test-results/test` folder.

### Unified test script

`scripts/run-tests.sh` runs the tests the same way locally and in CI. The same script is used in [olympic-tracker](https://gitlab.com/younesyousfipro-group/olympic-tracker): it detects the project type, then here runs `./gradlew clean test` and copies the JUnit XML reports (one per test class) into `test-results/`.

```bash
./scripts/run-tests.sh
```

| Exit code | Meaning |
|---|---|
| `0` | tests passed |
| other, usually `1` (passed through from Gradle) | tests failed, the reports are in `test-results/` |
| `2` | tests could not run: missing tool or no report produced (e.g. compilation error) |

Requires Bash and **JDK 21**. With a newer JDK (e.g. 25), the tests fail because Mockito cannot create its mocks: on macOS, run `export JAVA_HOME=$(/usr/libexec/java_home -v 21)` first.

## Packaging

When you’re ready to package the application for deployment, create a deployable WAR file:

```bash
./gradlew bootWar
```

The generated war file can be used with many application servers such as Tomcat, Wildfly...

## Run with Docker

The `Dockerfile` builds and packages the application in a multi-stage build: an `eclipse-temurin:21-jdk` stage runs `./gradlew bootWar`, then an `eclipse-temurin:21-jre-alpine` stage runs the WAR with `java -jar` as a non-root user. The WAR is executable (embedded Tomcat), so no application server is needed. Tests are not run in the image (see [Testing](#testing)).

With Docker Compose (recommended), the application and a PostgreSQL 13 database:

```bash
docker compose up -d --build   # build the image and start both services
docker compose ps              # wait for both services to be "(healthy)"
curl http://localhost:8080/api/workshops
```

Stop with `docker compose down` (data is kept in the `db-data` volume), or `docker compose down -v` to also delete the data.

| | |
|---|---|
| Port | 8080 for the API (all routes under `/api`); the database port is not published |
| Environment variables | `SPRING_DATASOURCE_*`, see [Configuration](#configuration); the URL host is `db`, the Compose service name |
| Start order | the API starts once the database health check (`pg_isready`) passes |
| Health checks | database: `pg_isready`; API: `GET /api/notions` every 10 s, after a 30 s start period |
| Persistence | named volume `db-data` on `/var/lib/postgresql/data` |
| Credentials | local development values, also the defaults in `application.properties`; never used outside Compose |
| Image size | ~390 MB (JRE + 54 MB WAR) |

The `POSTGRES_*` variables are only read when the volume is empty: after changing them, run `docker compose down -v`.

Design choices are recorded in [docs/decisions.md](docs/decisions.md).

## CI/CD pipeline

[`.gitlab-ci.yml`](.gitlab-ci.yml) runs on every branch push and on every tag (branch and tag pipelines only, so a merge request shows the status of its branch pipeline without running a second one). The same file is used in [olympic-tracker](https://gitlab.com/younesyousfipro-group/olympic-tracker): each job only runs in the repository whose project type it matches.

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
docker run --rm -v "$PWD":/src:ro eclipse-temurin:21-jdk bash -c '
  cp -r /src /app && cd /app && ./scripts/run-tests.sh'
```

### Container images

The `build` job pushes the image to the project's Container Registry (*Deploy → Container registry*), `registry.gitlab.com/younesyousfipro-group/workshop-api`, with two tags:

| Tag | Example | Pipeline | Moves | Use |
|---|---|---|---|---|
| commit SHA (`$CI_COMMIT_SHORT_SHA`) | `:a1b2c3d4` | every pipeline | never | know exactly which code runs; roll back |
| branch slug (`$CI_COMMIT_REF_SLUG`) | `:main` | branch pipeline | to the latest build of the branch | get the latest build of a branch |
| version (git tag without its `v`) | `:0.2.5` | tag pipeline, after a release | never | deploy a released version |

The release commit (`chore: release X.Y.Z`) starts no `main` pipeline (excluded by `workflow:rules`), so `:main` stays on the image of the commit before it; the two only differ by the version number in the project files. The release commit itself is built by its tag pipeline.

The image only contains the API: PostgreSQL comes from the official `postgres:13` image (see [Run with Docker](#run-with-docker)). To run the image of a branch locally with its database (public project, no login needed), give it the name Compose expects:

```bash
docker pull registry.gitlab.com/younesyousfipro-group/workshop-api:main
docker tag registry.gitlab.com/younesyousfipro-group/workshop-api:main workshop-api:local
docker compose up -d --no-build   # without --no-build, Compose may rebuild the image from the local sources
curl http://localhost:8080/api/workshops
```

**Cleanup.** A cleanup policy (*Settings → Packages and registries → Container registry → Cleanup policies*) runs every week: it keeps `:main`, every version tag and the 10 most recent tags (*Keep tags matching* `(?:main|\d+\.\d+\.\d+)`; GitLab anchors the pattern itself), and removes the other tags (commit SHAs, work branches) older than 30 days. Removing a SHA tag does not remove an image that still has its version tag; images left without any tag are deleted by GitLab after 24 hours. To remove an image by hand: *Deploy → Container Registry*, select all its tags (its commit SHA and its branch or version), *Delete selected*.

Images are built for `linux/amd64` (GitLab.com runners): on an Apple Silicon Mac, Docker Desktop runs them with emulation and prints a "platform does not match" warning.

The pipeline publishes a container image, not the Gradle package described in [Publishing to GitLab Registry](#publishing-to-gitlab-registry).

Design choices are recorded in [docs/decisions.md](docs/decisions.md).

## Releases and versioning

Versions are not chosen by hand: **semantic-release** computes them from the commit messages, then publishes the release. The setup is the same in [olympic-tracker](https://gitlab.com/younesyousfipro-group/olympic-tracker).

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
| `feat` | `feat: add workshop search endpoint` | minor: 0.2.4 → 0.3.0 |
| `fix`, `perf` | `fix: reject empty workshop title` | patch: 0.2.4 → 0.2.5 |
| `build` (project rule) | `build: upgrade JRE base image` | patch: the delivered image changes |
| `!` after the type, or a `BREAKING CHANGE:` footer | `feat!: rename API field` | major: 0.2.4 → 1.0.0 |
| `ci`, `docs`, `test`, `chore`, `refactor` | `docs: update README` | none |

How the next version is computed:

- Only the commits merged into `main` since the last version tag count; pushing to another branch never releases.
- The highest change wins, and the numbers on its right go back to zero: from 0.2.5, a `feat` gives 0.3.0, not 0.3.5.
- One merge request gives one release, whatever its number of commits: `fix` + `build` + `feat` + `docs` → 0.3.0, with the first three in the notes.
- A merge with only `docs`, `ci`, `test`, `chore` or `refactor` commits still runs the pipeline (tests, `:<sha>` and `:main` images) but publishes no version. A documentation-only push can skip the pipeline with `git push -o ci.skip`.
- A message that does not follow the convention is ignored without any error, so a fix written as `fixed the bug` is never released. Commits are written without a scope.

For example, from 0.2.5: an nginx or base image upgrade (`build:`) or a bug fix (`fix:`) gives 0.2.6; a new feature (`feat:`) gives 0.3.0.

### What happens on `main`

```
merge into main ─► pipeline "main": test → build (:<sha>, :main) → release
                                                                    │
  semantic-release:                                                 │
    1. finds the last version tag (e.g. v0.2.4)                     │
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
   git tag -a v0.2.4 7d12cbe -m "Version delivered by the client"
   git push origin v0.2.4
   ```
   That commit has no `.gitlab-ci.yml`, so the tag starts no pipeline.

When the token expires, the release job fails with an authentication error: create a new token and update the variable.

> **Same variable name as the client's Gradle publishing**: `build.gradle` also reads `GITLAB_TOKEN` (with `GITLAB_TOKEN_NAME` and `GITLAB_PROJECT_ID`) for `./gradlew publish` (see [Publishing to GitLab Registry](#publishing-to-gitlab-registry)). No CI job runs `gradlew publish`, so there is no conflict; a job added for it would receive the release token.

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

The chart [`helm/workshop-api-chart/`](helm/workshop-api-chart/) deploys the API image and its PostgreSQL database into two environments, `dev` and `staging`, each in its own namespace. Tested with Helm 4.3, Minikube 1.35 (Kubernetes 1.32, Docker driver) on an Apple Silicon Mac: the `linux/amd64` image runs with Docker Desktop's emulation.

| File | Content |
|---|---|
| `Chart.yaml` | chart name, chart `version` (bumped by hand when the chart changes), `appVersion` (the default image tag, written by `set-version.sh` at each release) |
| `values.yaml` | every value with its default, under `app:` (the API) and `db:` (PostgreSQL) |
| `values-dev.yaml`, `values-staging.yaml` | only the values that differ in that environment |
| `templates/` | one file per object, below |

| Template | Object | Role |
|---|---|---|
| `secret.yaml` | Secret `<release>-db-secret` | database username and password, read by both Deployments |
| `pvc-db.yaml` | PersistentVolumeClaim `<release>-db-pvc` | 1 Gi for the database files; kept by `helm uninstall` |
| `deployment-db.yaml` | Deployment `<release>-db-deployment`, 1 Pod `postgres:13` | the database |
| `service-db.yaml` | headless Service `<release>-db-service` | DNS name of the database, used in the datasource URL |
| `deployment-app.yaml` | Deployment `<release>-app-deployment` | the API |
| `service-app.yaml` | `LoadBalancer` Service `<release>-app-service` | access to the API from outside the cluster |

Values:

| Key | Default | Used for |
|---|---|---|
| `app.replicas` | `1` | API Deployment `replicas` |
| `app.image` | `registry.gitlab.com/younesyousfipro-group/workshop-api` | image name, without tag |
| `app.tag` | `""` | image tag; empty = `appVersion` from `Chart.yaml` |
| `app.imagePullPolicy` | `IfNotPresent` | `Always` for a moving tag (`main`), otherwise the node keeps the first image it pulled |
| `app.port` | `8080` | `containerPort`, readiness probe, Service `port` and `targetPort` (the port Spring Boot listens on) |
| `app.imagePullSecret` | `workshop-api-registry` | pull secret name; empty = no `imagePullSecrets` |
| `app.resources` | requests `250m` / `512Mi`, limits `1` / `768Mi` | API container `resources` |
| `db.image` | `postgres:13` | database image, with its tag |
| `db.port` | `5432` | `containerPort`, Service `port` and `targetPort`, datasource URL (the port PostgreSQL listens on) |
| `db.username` | `postgres` | Secret, read by PostgreSQL and by the API |
| `db.password` | `oc2024` | Secret, read by PostgreSQL and by the API. Sandbox value, already public in `docker-compose.yml` |
| `db.database` | `workshop-organizer-database` | `POSTGRES_DB` and datasource URL |
| `db.resources` | requests `100m` / `256Mi`, limits `500m` / `512Mi` | database container `resources` |

Fixed in the templates: one database replica with `strategy: Recreate`, in every environment (two PostgreSQL must never share the same files), PVC size 1 Gi, Service types, readiness probes (API `GET /api/notions`, database `pg_isready`). Object names, labels and the references between objects (datasource host, Secret, PVC) are all built from the release name, so they always match.

Differences between the two projects:

| | olympic-tracker | workshop-api |
|---|---|---|
| Kubernetes objects | 2: Deployment + `LoadBalancer` Service | 6: Secret, PVC, Deployment + headless Service (PostgreSQL), Deployment + `LoadBalancer` Service (API) |
| Values | `app:` | `app:` and `db:` |
| Images | `olympic-tracker` | `workshop-api` + `postgres:13` (Docker Hub, no pull secret) |
| Service → container port | 80 → 8080 | 8080 → 8080 |
| Configuration | none (static files, data inside the image) | database URL, username and password as environment variables |
| Secrets | pull secret only (created by hand) | pull secret (created by hand) + database Secret (rendered from the values) |
| Readiness probe | `GET /` | API: `GET /api/notions`; database: `pg_isready` |
| State | stateless: deleting the Pod loses nothing | PVC: data survives the Pod; `strategy: Recreate` |
| Start order | — | none: the API restarts until the database is ready |
| Staging replicas | 2 Pods | API 2 Pods, database 1 |
| Per-environment values | image tag, replicas, resources | the same, plus the database password (given at install time in staging) |
| `helm uninstall` | nothing lost | PVC kept, so the data; deleting it is a separate command |

### Environments

One chart, one image, two namespaces. The image carries no environment: only the values change.

| | dev | staging |
|---|---|---|
| Namespace | `dev` | `staging` |
| Values file | `values-dev.yaml` | `values-staging.yaml` |
| API image tag | `main`: latest build of `main` | none, so `appVersion`: latest release (`0.2.5`) |
| `imagePullPolicy` | `Always` (moving tag) | `IfNotPresent` (default) |
| API replicas | 1 (default) | 2 |
| Database replicas | 1 | 1 (fixed in the template) |
| API resources | requests `250m` / `512Mi`, limits `1` / `768Mi` (default) | requests `500m` / `768Mi`, limits `1` / `1Gi` |
| Database resources | requests `100m` / `256Mi`, limits `500m` / `512Mi` (default) | same |
| Database password | sandbox default (`oc2024`) | generated, given at install time, never committed |
| Data | PVC `workshop-api-db-pvc` in `dev` | its own PVC `workshop-api-db-pvc` in `staging` |
| Pull secret | `workshop-api-registry` in `dev` | `workshop-api-registry` in `staging` |

There is no branch per environment: `main` is the only long-lived branch. An image is promoted, not rebuilt for each environment: `dev` shows the latest merge on `main`, `staging` the latest release. Deployments are run by hand (no deploy job in the pipeline: GitLab.com runners cannot reach Minikube).

Measured idle in `dev` with `kubectl top` (metrics-server addon): API `14m` CPU / `341Mi` memory, database `4m` / `84Mi`. Requests of both projects in `dev` and `staging`: about 2.55 CPU and 3 Gi, against the 4 CPU / 6 Gi given to Minikube. Compare with these numbers, not with the percentages of `kubectl describe node`: with the Docker driver the node reports the resources of the Docker Desktop VM, not the limits of the `minikube` container.

The commands below use a shell variable for the chart path, and `<env>` for `dev` or `staging`:

```bash
C=helm/workshop-api-chart
```

### 1. Namespaces and registry credentials (once per cluster)

The project is public, so the image can be pulled anonymously; the chart still uses a pull secret, as a private registry would require. The Secret is created outside the chart on purpose: a credential is prepared with the cluster and its value never goes into Git (see [docs/decisions.md](docs/decisions.md#helm-chart-2026-11-04)). A Pod only reads Secrets of its own namespace: one Secret per namespace.

1. On GitLab: *Settings → Repository → Deploy tokens → Add token*, scope **`read_registry`** only, with an expiration date. Keep the username and token (shown once) in a password manager.
2. Create the namespaces (`AlreadyExists` is fine: the namespaces may have been created for another project), then the Secret in each of them (the token is typed without echo and stays out of the shell history):

   ```bash
   kubectl config current-context      # must be minikube
   kubectl create namespace dev
   kubectl create namespace staging
   read -rs TOKEN
   for ns in dev staging; do
     kubectl create secret docker-registry workshop-api-registry -n "$ns" \
       --docker-server=registry.gitlab.com \
       --docker-username=<deploy token username> \
       --docker-password="$TOKEN"
   done
   unset TOKEN
   ```

The kubelet (not the container) uses this Secret to pull the image. When the token expires, the Pod fails with `ErrImagePull`.

### 2. Check the chart

```bash
helm lint --strict $C -f $C/values-<env>.yaml
diff <(helm template workshop-api $C) <(helm template workshop-api $C -f $C/values-<env>.yaml)   # only the overrides
minikube start
helm install workshop-api $C -n <env> -f $C/values-<env>.yaml --dry-run=server --hide-secret   # validated by the API server, nothing created
```

`lint` checks the chart structure and the template syntax, not the Kubernetes fields: the server dry run does. A dry run prints every manifest, Secrets included: `--hide-secret` masks them.

### 3. Install and check

`dev` uses the sandbox password from `values.yaml`:

```bash
helm install workshop-api $C -n dev -f $C/values-dev.yaml
```

`staging` gets its own password. Generate it once and keep it in a password manager: every later `helm upgrade` of `staging` needs it (see [Update](#6-update)). Hex only, because `--set` reads `,` and `=` as separators:

```bash
openssl rand -hex 16
read -rs DB_PASSWORD
helm install workshop-api $C -n staging -f $C/values-staging.yaml --set db.password="$DB_PASSWORD"
unset DB_PASSWORD
```

Then, in each namespace:

```bash
helm list -A                                                 # one workshop-api release per namespace
kubectl get pods -n <env> -w                                 # dev: API + database, staging: 2 API + database, all 1/1 Running
kubectl describe pods -n <env> -l app=workshop-api-app | grep -E "Image:|Pulled"   # dev: :main, staging: :0.2.5
kubectl get pvc -n <env>                                     # workshop-api-db-pvc Bound
kubectl get endpointslices -n <env> -l kubernetes.io/service-name=workshop-api-app-service   # one IP per API Pod
```

Same release name in both namespaces: the objects have the same names, only the namespace differs. Helm records each release revision in a Secret of the namespace (`sh.helm.release.v1.workshop-api.v1`).

### 4. Call the API

```bash
minikube service workshop-api-app-service -n <env> --url     # keep this terminal open
```

The command prints `http://127.0.0.1:<port>` (a new local port each time) and holds a tunnel to the Service (the node IP is not reachable with the Docker driver on macOS). In another terminal, with the printed port:

```bash
URL=http://127.0.0.1:54321
curl -X POST -H 'Content-Type: application/json' -d '{"name":"Helm"}' $URL/api/notions
curl $URL/api/notions
```

Each environment has its own database: a notion created in `dev` does not appear in `staging`.

### 5. Check persistence

The data survives a new database Pod:

```bash
kubectl delete pod -n <env> -l app=workshop-api-db
kubectl get pods -n <env> -w
curl $URL/api/notions
```

The notion is still there. The first call after the restart may fail while the API reopens its connections: call again.

It also survives the removal of the release, since the PVC is kept and taken back by a release of the same name (in `staging`, give the same password again):

```bash
helm uninstall workshop-api -n dev            # prints: These resources were kept due to the resource policy
helm install workshop-api $C -n dev -f $C/values-dev.yaml
```

Then start `minikube service` again (new port) and call `/api/notions`: the notion is still there.

### 6. Update

| Change | Command |
|---|---|
| new build of `main`, to `dev` | `kubectl rollout restart deployment workshop-api-app-deployment -n dev` (same values, so `helm upgrade` would not replace the Pods; the new Pods pull `:main` again) |
| new release, to `staging` | `git pull` (the release commit updates `appVersion`), then `read -rs DB_PASSWORD` and `helm upgrade workshop-api $C -n staging -f $C/values-staging.yaml --set db.password="$DB_PASSWORD"` |
| chart or values changed | `helm upgrade workshop-api $C -n <env> -f $C/values-<env>.yaml`, plus `--set db.password=...` in `staging` |

⚠️ A `helm upgrade` of `staging` without `--set db.password` puts the sandbox default back in the Secret. PostgreSQL keeps the password of its first start, so the API is refused at its next restart (`password authentication failed`).

### 7. Remove

```bash
helm uninstall workshop-api -n <env>
kubectl delete pvc workshop-api-db-pvc -n <env>     # deletes the data
kubectl delete secret workshop-api-registry -n <env>
```

`kubectl delete namespace <env>` deletes everything in it, the releases of other projects included.

### Troubleshooting

| Symptom | Likely cause | Look at |
|---|---|---|
| `helm install` fails: `cannot re-use a name that is still in use` | the release already exists in this namespace | `helm list -n <env>`; `helm uninstall workshop-api -n <env>` first |
| Service `workshop-api-app-service` not found | release installed under another name (objects are named after it), or wrong namespace | `helm list -A`, `kubectl get svc -n <env>` |
| `helm template` or `lint` fails | template syntax, indentation | the line given in the error |
| `ErrImagePull` / `ImagePullBackOff` | wrong image name or tag, pull secret missing in this namespace or token expired | `kubectl describe pod -n <env> -l app=workshop-api-app` (Events) |
| `CreateContainerConfigError` | Secret or key missing | `kubectl describe pod -n <env>` (Events) |
| API in `CrashLoopBackOff` with `UnknownHostException` | database Pod not ready yet (headless Service: no DNS record without a ready Pod); lasts if the database never gets ready | `kubectl logs -n <env> -l app=workshop-api-app --previous`, `kubectl get pods -n <env>` |
| API logs `password authentication failed` | `db.password` changed while the PVC already holds a database (the `POSTGRES_*` variables are only read when the volume is empty), e.g. a `staging` upgrade without `--set db.password` | give the old password back, or delete the PVC to start from an empty database |
| database Pod `Pending` | PVC not bound | `kubectl get pvc -n <env>`, `kubectl describe pvc workshop-api-db-pvc -n <env>` |
| `Running` but `0/1` | readiness probe failing | `kubectl describe pod -n <env>`, `kubectl logs -n <env>` |
| `dev` still runs an old `main` | Pods not restarted since the last build | `kubectl rollout restart deployment workshop-api-app-deployment -n dev` |
| PV still `Released` after deleting the PVC (Minikube) | Minikube's provisioner only deletes the volumes it created since its last start (log: `identity annotation on PV does not match ours`) | `kubectl get pv`; `kubectl delete pv <name>`, then `minikube ssh -- sudo rm -rf /tmp/hostpath-provisioner/<env>/<pvc name>` (a PVC created again with that name would find the old files) |

With a fixed tag (`staging`) the node keeps the image and does not pull it again (`already present on machine`), so the pull secret is not used. To test it, remove the image from the node first: `minikube image rm registry.gitlab.com/younesyousfipro-group/workshop-api:0.2.5`.

Design choices are recorded in [docs/decisions.md](docs/decisions.md#helm-chart-2026-11-04) and [docs/decisions.md](docs/decisions.md#environments-2026-11-05). The chart replaces the plain manifests of the `k8s/` folder (removed, see the decisions).

## Publishing to GitLab Registry

To publish your application to a GitLab registry, follow these steps:

1. Set up your GitLab project.
2. Ensure you have the following environment variables configured:

   - GITLAB_PROJECT_ID: The ID of your GitLab project.
   - GITLAB_TOKEN_NAME: The name of the GitLab access token.
   - GITLAB_TOKEN: Your GitLab access token.

3. Execute the following command to publish your application:
   ```bash
   ./gradlew publish
   ```
   Remember to replace placeholders with actual values specific to your project.

Feel free to enhance this README with additional details, such as API endpoints, security considerations, and deployment instructions. Happy organizing! 🚀
