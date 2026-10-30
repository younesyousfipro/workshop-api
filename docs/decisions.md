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

## Containerization (2026-10-30)

### Image

| Decision | Rejected | Reason |
|---|---|---|
| Multi-stage `Dockerfile`: JDK stage builds, JRE stage runs | single stage | the JDK and Gradle are only needed to build; the final image holds the JRE and the WAR |
| Build image `eclipse-temurin:21-jdk` | `gradle:8.7-jdk21` | the Gradle wrapper stays the single source of the Gradle version, as in the README; Temurin is the Adoptium JDK the README was tested with |
| Runtime image `eclipse-temurin:21-jre-alpine` | JDK image, Ubuntu-based JRE | a JRE is enough to run; Alpine is smaller and ships `wget` (BusyBox) for the health check |
| Floating tags (`21-jdk`, `21-jre-alpine`) | exact version or digest | same choice as `olympic-tracker`: security patches are picked up automatically |
| Build files copied before the sources, then `./gradlew dependencies` | one `COPY` of the whole project | Gradle and the dependencies stay in the layer cache while the build files do not change |
| WAR run with `java -jar` | Tomcat server image (README: "WAR for Tomcat") | `bootWar` produces an executable WAR with an embedded Tomcat |
| WAR copied with `*.war` and renamed `app.war` | exact file name | the file name contains the project version, which each release will change |
| Non-root user `app` | root (image default) | limits the impact if the app is compromised; costs two lines since port 8080 is above 1024 and the app only writes to `/tmp`; Kubernetes `restricted` profile requires it. `olympic-tracker` also runs as non-root since 2026-10-30 |
| Tests not run in the image (`bootWar` does not run them) | `./gradlew build` in the build stage | tests get their own CI job with a JUnit report (Ex2); same choice as `olympic-tracker` |
| `.dockerignore` excludes `build`, `.gradle`, `src/main/java-generated`, `.git` | no `.dockerignore` | smaller build context; generated OpenAPI sources are rebuilt in the image, a stale local copy must not slip in |

### Compose

| Decision | Rejected | Reason |
|---|---|---|
| Client's `docker-compose.yml` completed, service names `app` and `db` kept | rewrite | `db` is the host name in the client's datasource URL |
| Image named `workshop-api:local`, built by Compose (`build: .`) | `workshop-organizer` built by hand | same name everywhere (repository, image, chart); one command to build and run |
| `postgres:13` kept | PostgreSQL 14+, Alpine variant | version stated by the client; a major upgrade is a data migration, so the client's call. **PostgreSQL 13 is end-of-life since November 2025: upgrade recommended to the client.** Debian-based because Alpine (musl) sorts strings differently |
| Named volume `db-data` | no volume, bind mount | data survives `docker compose down`; managed by Docker, no host path to create |
| Database health check `pg_isready -h 127.0.0.1` and `depends_on: condition: service_healthy` | `depends_on` alone | `depends_on` alone only waits for the container to start, not for Postgres to accept connections; `-h` forces TCP because on first init Postgres runs a temporary server on the Unix socket only |
| API health check `GET /api/notions` with a 30 s start period | Spring Boot Actuator, no health check | Actuator would change the client's `build.gradle`; this route is light and goes through the database |
| Database port 5432 not published | `"5432:5432"` | the API reaches the database over the Compose network; avoids a conflict with a local Postgres |
| Credentials in clear in `docker-compose.yml` | `.env` file ignored by git | local development values, already public in the client's `application.properties`; a `.env` would break the one-command `docker compose up -d`. Deployed environments get Kubernetes Secrets (Ex3) |
| Client's default password in `application.properties` left as is | removing it | client code; overridden by `SPRING_DATASOURCE_PASSWORD` at runtime. Recommended to the client: remove it from the code |
| SQL dump in `db/` not mounted | mount in `/docker-entrypoint-initdb.d` | Hibernate creates the tables (`ddl-auto=update`) |

## Test script (2026-10-30)

| Decision | Rejected | Reason |
|---|---|---|
| Bash script `scripts/run-tests.sh` | Python | the script only chains commands; Bash is in every Debian-based CI image, Python is not guaranteed. Consequence: the CI image must provide Bash (not the case of Alpine images by default) |
| Same file in both repositories, project type detected from marker files (`package.json` + `angular.json`, or `gradlew`) | one script per repository; shared `ci-templates` project | one behaviour for both apps, and each repository stays self-contained. A shared project remains possible (question for the mentor) |
| Reports collected into `test-results/` | changing the output folder in `build.gradle` | client configuration untouched; the CI only needs one report path for both apps |
| Reports collected even when tests fail; the run fails if no report is found | stop at the first failure | GitLab needs the report to show which test failed; a run without a report means no test was checked (e.g. compilation error) |
| Exit code of the test tool passed through; `2` when the tests could not run | always `1` | tells "the code is broken" from "the environment is broken"; keeps tool-specific codes (e.g. 137 = killed, out of memory) |
| JDK 21 required, Java version not checked by the script | version check in the script | under Java 25 the tests fail (Mockito cannot create its mocks). The CI image will be a JDK 21; the check would only help on a developer machine |
| `test-results/` ignored by git | — | generated output, published by the CI |
