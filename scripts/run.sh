#!/usr/bin/env bash
# 컬렉터를 인자로 받아 게시판 서버를 실행한다.
#
#   scripts/run.sh <g1|shenandoah|zgc|zgc-gen> [profile]
#
#   profile: default(생략) | leak-static | leak-threadlocal | leak-listener
#
# 결과는 results/<collector>/<profile>/ 아래에 남는다.
#   gc.log     -Xlog:gc*,safepoint
#   rec.jfr    JFR 녹화 (path-to-gc-roots=true 로 OldObjectSample 경로 포함)
#   java-version.txt, machine.txt, jvm-flags.txt
#
# 환경변수
#   HEAP        힙 크기 (기본 1g). Xms=Xmx 로 고정한다.
#   MAX_PAUSE   G1 의 MaxGCPauseMillis (기본 200)
#   BOARD_SEED_COUNT  더미 게시글 수 (기본 10000)
#   JAVA_HOME   사용할 JDK. Temurin/Corretto 21 이어야 셰넌도어가 있다.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${1:-}"
PROFILE="${2:-default}"
HEAP="${HEAP:-1g}"
MAX_PAUSE="${MAX_PAUSE:-200}"
JAR="$ROOT/app/build/libs/app.jar"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"

usage() {
  echo "usage: $0 <g1|shenandoah|zgc|zgc-gen> [default|leak-static|leak-threadlocal|leak-listener]" >&2
  exit 2
}

case "$COLLECTOR" in
  g1)         GC_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=$MAX_PAUSE" ;;
  shenandoah) GC_OPTS="-XX:+UseShenandoahGC" ;;
  zgc)        GC_OPTS="-XX:+UseZGC" ;;                       # JDK 21: 비세대 ZGC
  zgc-gen)    GC_OPTS="-XX:+UseZGC -XX:+ZGenerational" ;;    # JDK 21: 세대 구분 ZGC
  *)          usage ;;
esac

case "$PROFILE" in
  default|leak-static|leak-threadlocal|leak-listener) ;;
  *) usage ;;
esac

if [[ ! -f "$JAR" ]]; then
  echo "[run] app.jar 이 없어 빌드합니다..." >&2
  (cd "$ROOT" && ./gradlew -q :app:bootJar)
fi

OUT="$ROOT/results/$COLLECTOR/$PROFILE"
mkdir -p "$OUT"
rm -f "$OUT/gc.log" "$OUT/rec.jfr"

# 재현성을 위한 환경 기록
"$JAVA_BIN" -version > "$OUT/java-version.txt" 2>&1
{
  echo "date: $(date -Iseconds)"
  echo "uname: $(uname -a)"
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "cpu: $(sysctl -n machdep.cpu.brand_string) x $(sysctl -n hw.ncpu)"
    echo "mem: $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB"
  else
    echo "cpu: $(nproc) cores"
    echo "mem: $(free -g | awk '/Mem:/ {print $2}') GB"
  fi
} > "$OUT/machine.txt"

COMMON_OPTS=(
  -Xms"$HEAP" -Xmx"$HEAP"
  -XX:+AlwaysPreTouch
  "-Xlog:gc*,safepoint:file=$OUT/gc.log:time,uptime,level,tags"
  "-XX:StartFlightRecording:settings=profile,path-to-gc-roots=true,filename=$OUT/rec.jfr,dumponexit=true"
  -XX:+HeapDumpOnOutOfMemoryError "-XX:HeapDumpPath=$OUT/oom.hprof"
)

SPRING_OPTS=()
if [[ "$PROFILE" != "default" ]]; then
  SPRING_OPTS+=("--spring.profiles.active=$PROFILE")
fi

# shellcheck disable=SC2086
echo "$JAVA_BIN ${COMMON_OPTS[*]} $GC_OPTS -jar $JAR ${SPRING_OPTS[*]:-}" > "$OUT/jvm-flags.txt"

echo "[run] collector=$COLLECTOR profile=$PROFILE heap=$HEAP -> $OUT" >&2
echo "[run] 서버가 뜨면 다른 터미널에서: k6 run load/board.js" >&2
echo "[run] 힙 덤프: scripts/dump.sh $COLLECTOR $PROFILE" >&2

# shellcheck disable=SC2086
exec "$JAVA_BIN" "${COMMON_OPTS[@]}" $GC_OPTS -jar "$JAR" "${SPRING_OPTS[@]}"
