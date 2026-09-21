# 코어·메모리를 제한한 컨테이너에서 서버를 띄우기 위한 이미지.
# jar 는 호스트에서 ./gradlew :app:bootJar 로 먼저 만들고 복사한다 (컨테이너 안에서 Gradle 을 돌리지 않는다).
# eclipse-temurin:21 (JDK) 을 쓰는 이유: jcmd(힙 덤프)·jfr 도구가 필요하고, Temurin 리눅스 빌드에는 셰넌도어가 들어 있다.
FROM eclipse-temurin:21

WORKDIR /lab
COPY app/build/libs/app.jar /lab/app.jar

# gc.log, rec.jfr, hprof 는 /lab/results 에 쓰고, 호스트의 results/ 를 여기에 마운트한다.
VOLUME ["/lab/results"]
EXPOSE 8080

# 실제 JVM 옵션은 scripts/run-docker.sh 가 JAVA_TOOL_OPTIONS 로 넘긴다.
ENTRYPOINT ["java", "-jar", "/lab/app.jar"]
