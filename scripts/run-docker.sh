#!/usr/bin/env bash
# 코어·메모리를 제한한 Docker 컨테이너에서 게시판 서버를 실행한다. (run.sh 의 컨테이너 버전)
#
#   scripts/run-docker.sh <g1|shenandoah|zgc|zgc-gen> [profile]
#
# 환경변수
#   CPUS   컨테이너 CPU 제한 (기본 2)      → JVM 이 보는 코어 수. GC 스레드 수·동시 GC 여유가 여기서 결정된다.
#   MEM    컨테이너 메모리 제한 (기본 2g)   → 힙(HEAP) + 메타스페이스 + 스레드 스택 + GC 자료구조 여유. HEAP 의 2배 정도가 안전.
#   HEAP   JVM 힙 (기본 1g, Xms=Xmx 고정)
#   MAX_PAUSE, BOARD_SEED_COUNT  run.sh 와 동일
#
# 결과는 run.sh 와 같은 results/<collector>/<profile>/ 에 남는다 (호스트 폴더를 컨테이너 /lab/results 에 마운트).
# 부하(k6)는 호스트에서 그대로: k6 run load/board.js   (8080 포트 매핑)
# 힙 덤프: scripts/dump.sh <collector> [profile] [tag]   (컨테이너가 떠 있으면 자동으로 docker exec 로 뜬다)
#
# 주의
# - Docker Desktop(macOS) 의 컨테이너는 Linux VM 위에서 돈다. 즉 결과는 "리눅스 aarch64, 코어 N개" 환경이지 macOS 가 아니다.
#   컬렉터 간 상대 비교에는 오히려 서버 환경에 가까워 좋다. run.sh(호스트) 결과와 섞어서 비교하지 말 것.
# - --cpus 는 CFS 쿼터라 "코어 2개 고정" 이 아니라 "매 주기 2코어 분량". JVM 은 이를 availableProcessors=2 로 읽는다.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${1:-}"
PROFILE="${2:-default}"
CPUS="${CPUS:-2}"
MEM="${MEM:-2g}"
HEAP="${HEAP:-1g}"
MAX_PAUSE="${MAX_PAUSE:-200}"
IMAGE="gc-roots-board-lab:latest"
NAME="gc-lab"

usage() {
  echo "usage: $0 <g1|shenandoah|zgc|zgc-gen> [default|leak-static|leak-threadlocal|leak-listener]" >&2
  exit 2
}

case "$COLLECTOR" in
  g1)         GC_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=$MAX_PAUSE" ;;
  shenandoah) GC_OPTS="-XX:+UseShenandoahGC" ;;
  zgc)        GC_OPTS="-XX:+UseZGC" ;;
  zgc-gen)    GC_OPTS="-XX:+UseZGC -XX:+ZGenerational" ;;
  *)          usage ;;
esac
case "$PROFILE" in
  default|leak-static|leak-threadlocal|leak-listener) ;;
  *) usage ;;
esac

command -v docker >/dev/null || { echo "[docker] docker 명령을 찾지 못했습니다. Docker Desktop 이 켜져 있나요?" >&2; exit 1; }

# jar 가 없거나 소스보다 오래됐으면 빌드
JAR="$ROOT/app/build/libs/app.jar"
if [[ ! -f "$JAR" ]] || [[ -n "$(find "$ROOT/app/src" -newer "$JAR" -type f 2>/dev/null | head -1)" ]]; then
  echo "[docker] app.jar 빌드..." >&2
  (cd "$ROOT" && ./gradlew -q :app:bootJar)
fi

echo "[docker] 이미지 빌드 ($IMAGE)..." >&2
docker build -q -t "$IMAGE" "$ROOT" >/dev/null

# 이전 컨테이너 정리
docker rm -f "$NAME" >/dev/null 2>&1 || true

OUT_HOST="$ROOT/results/$COLLECTOR/$PROFILE"
OUT_CTR="/lab/results/$COLLECTOR/$PROFILE"
mkdir -p "$OUT_HOST"
rm -f "$OUT_HOST/gc.log" "$OUT_HOST/rec.jfr"

# 환경 기록 (컨테이너 관점). -XshowSettings:system 은 컨테이너 안에서 JVM 이 인식한 CPU 수·메모리 제한을 찍어준다.
docker run --rm --cpus="$CPUS" --memory="$MEM" --entrypoint java "$IMAGE" -version > "$OUT_HOST/java-version.txt" 2>&1
{
  echo "date: $(date -Iseconds)"
  echo "runtime: docker (Docker Desktop VM), image=$IMAGE"
  echo "limits: --cpus=$CPUS --memory=$MEM  heap=$HEAP"
  echo "host: $(uname -a)"
  echo "--- JVM 이 본 컨테이너 리소스 ---"
  docker run --rm --cpus="$CPUS" --memory="$MEM" --entrypoint java "$IMAGE" -XshowSettings:system -version 2>&1 | grep -v "^openjdk\|^OpenJDK"
  echo "--- GC 스레드 ---"
  docker run --rm --cpus="$CPUS" --memory="$MEM" --entrypoint java "$IMAGE" $GC_OPTS -XX:+PrintFlagsFinal -version 2>/dev/null \
    | awk '/ParallelGCThreads|ConcGCThreads/ {printf "%s=%s\n", $2, $4}'
} > "$OUT_HOST/machine.txt"

JVM_OPTS=(
  -Xms"$HEAP" -Xmx"$HEAP"
  -XX:+AlwaysPreTouch
  "-Xlog:gc*,safepoint:file=$OUT_CTR/gc.log:time,uptime,level,tags"
  "-XX:StartFlightRecording:settings=profile,path-to-gc-roots=true,filename=$OUT_CTR/rec.jfr,dumponexit=true"
  -XX:+HeapDumpOnOutOfMemoryError "-XX:HeapDumpPath=$OUT_CTR/oom.hprof"
)
SPRING_OPTS=()
[[ "$PROFILE" != "default" ]] && SPRING_OPTS+=("--spring.profiles.active=$PROFILE")

# shellcheck disable=SC2086
echo "docker run --cpus=$CPUS --memory=$MEM ... java ${JVM_OPTS[*]} $GC_OPTS -jar /lab/app.jar ${SPRING_OPTS[*]+"${SPRING_OPTS[*]}"}" > "$OUT_HOST/jvm-flags.txt"

echo "[docker] collector=$COLLECTOR profile=$PROFILE cpus=$CPUS mem=$MEM heap=$HEAP -> $OUT_HOST" >&2
echo "[docker] 서버가 뜨면 다른 터미널에서: k6 run load/board.js" >&2
echo "[docker] 힙 덤프: scripts/dump.sh $COLLECTOR $PROFILE mid   /  중지: Ctrl+C (JFR 은 종료 시 확정)" >&2

# --init: Ctrl+C(SIGINT) 가 JVM 까지 전달돼 JFR dumponexit 이 동작하도록
# shellcheck disable=SC2086
exec docker run --rm --init --name "$NAME" \
  --cpus="$CPUS" --memory="$MEM" --memory-swap="$MEM" \
  -p 8080:8080 \
  -e BOARD_SEED_COUNT="${BOARD_SEED_COUNT:-10000}" \
  -v "$ROOT/results:/lab/results" \
  --entrypoint java "$IMAGE" \
  "${JVM_OPTS[@]}" $GC_OPTS -jar /lab/app.jar ${SPRING_OPTS[@]+"${SPRING_OPTS[@]}"}
