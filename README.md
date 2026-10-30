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
