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
| Start from the client's version: tag **`v0.2.4`** set by hand on the client's last commit (`7d12cbe`, version in `build.gradle`: `0.2.4`) | first release `1.0.0` | keeps the client's version history; in SemVer, `1.0.0` means "stable API", a product decision for the client. The first release then lists exactly what the industrialization added |
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

The first release (0.2.5) was published, but its tag pipeline was skipped and no `:0.2.5` image was built: GitLab reads `[skip ci]` in the message of the commit, and the version tag points to the release commit.

| Decision | Rejected | Reason |
|---|---|---|
| Release commit message without `[skip ci]`; the release commit is excluded from **branch** pipelines by `workflow:rules` (`$CI_COMMIT_BRANCH && $CI_COMMIT_TITLE =~ /^chore: release /` → `never`) | keeping `[skip ci]` | `[skip ci]` also skips the tag pipeline that builds the versioned image. In a tag pipeline `$CI_COMMIT_BRANCH` is empty, so the rule does not apply there |
| | dropping `[skip ci]` without a rule | the release commit would start a `main` pipeline too: two builds of the same commit at the same time, the SHA image tag overwritten, a few more CI minutes per release (no loop though: a `chore` commit never triggers a version) |
| Missing `:0.2.5` image built by a pipeline run by hand on the tag (*Build → Pipelines → New pipeline*) | retagging the image of the merge commit | that image was built before the version existed (its project files say the previous version); a manual pipeline is not skipped by `[skip ci]` |

## Container registry cleanup (2026-11-02)

| Decision | Rejected | Reason |
|---|---|---|
| GitLab **cleanup policy**, weekly: keep `main`, every version tag (`(?:main\|\d+\.\d+\.\d+)`) and the 10 most recent tags; remove the other tags (`.*`) older than 30 days | no cleanup; a cleanup job in the pipeline | every push adds a SHA-tagged image that nothing removes. The policy is a built-in setting, no code or CI minutes. Released versions are never removed (keep rules win over remove rules) |
| Pattern written as a group without `^`/`$` | `^(main\|…)$` | GitLab wraps the pattern in `\A…\Z` itself; the group keeps both anchors on every alternative |
| One-time manual cleanup: all images from the setup and test pipelines deleted, only two kept (`main` + `a4663338`, `0.2.5` + `e8c21abc`) | waiting for the policy | the policy only removes tags older than 30 days; the setup images have no use. A registry deletes images through their tags: an image is removed once no tag points to it |
