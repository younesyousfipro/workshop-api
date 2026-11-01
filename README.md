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

The release commit (`chore: release X.Y.Z [skip ci]`) starts no `main` pipeline, so `:main` stays on the image of the commit before it; the two only differ by the version number in the project files.

The image only contains the API: PostgreSQL comes from the official `postgres:13` image (see [Run with Docker](#run-with-docker)). To run the image of a branch locally with its database (public project, no login needed), give it the name Compose expects:

```bash
docker pull registry.gitlab.com/younesyousfipro-group/workshop-api:main
docker tag registry.gitlab.com/younesyousfipro-group/workshop-api:main workshop-api:local
docker compose up -d --no-build   # without --no-build, Compose may rebuild the image from the local sources
curl http://localhost:8080/api/workshops
```

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

With several commits since the last version, the highest change wins. A message that does not follow the convention is ignored without any error, so a fix written as `fixed the bug` is never released. Commits are written without a scope.

### What happens on `main`

```
merge into main ─► pipeline "main": test → build (:<sha>, :main) → release
                                                                    │
  semantic-release:                                                 │
    1. finds the last version tag (e.g. v0.2.4)                     │
    2. reads the commits since that tag, computes the next version  │
    3. writes CHANGELOG.md and the version in the project files     │
    4. commits them to main ("chore: release X.Y.Z [skip ci]")      │
    5. tags that commit vX.Y.Z and creates the GitLab release ◄─────┘
                                                                    │
  the pushed tag starts a pipeline "vX.Y.Z": test → build (:<sha>, :X.Y.Z)
```

- No releasable commit since the last tag: the job ends green without releasing.
- `[skip ci]` keeps the release commit from starting another `main` pipeline.
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
| prepare | `@semantic-release/git` | commits `CHANGELOG.md` and the version files (missing files are skipped, so the list covers both repositories) |
| publish | `@semantic-release/gitlab` | creates the GitLab release; comments on the merge requests it includes, opens an issue if the release fails |

`scripts/set-version.sh X.Y.Z` writes the version into the project file. It detects the project type like `run-tests.sh` and fails (exit code 2) if the file does not show the new version afterwards. It does not depend on semantic-release and can be run by hand.

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

semantic-release recommends keeping the version in git tags only and not committing during a release. The instructions of this project require the version to be synchronized in the project files, so the version files and `CHANGELOG.md` are committed by `@semantic-release/git`. The cost: a token allowed to push to `main`, `[skip ci]` on the release commit, and a pull after each release. See [docs/decisions.md](docs/decisions.md).

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
