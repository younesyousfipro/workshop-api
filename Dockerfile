FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
# Build files first: the Gradle and dependencies layer stays cached as long as they do not change
COPY gradlew settings.gradle build.gradle ./
COPY gradle gradle
RUN ./gradlew dependencies --no-daemon
COPY src src
RUN ./gradlew bootWar --no-daemon

FROM eclipse-temurin:21-jre-alpine
# Non-root user (best practice): if the app is compromised, the attacker only gets this user's minimal rights, not root
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
# The WAR name contains the project version, which will change with each release
COPY --from=build /app/build/libs/*.war app.war
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.war"]
