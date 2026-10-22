FROM eclipse-temurin:25-jre
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/* \
    && groupadd --system app && useradd --system --gid app --home-dir /app app
WORKDIR /app
COPY --chown=app:app build/libs/*-SNAPSHOT.jar app.jar
USER app
EXPOSE 8090
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
