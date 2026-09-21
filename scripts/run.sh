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

# ---- JDK 21 선택 ----
# 셸의 JAVA_HOME 이 17 을 가리키고 있어도 되도록, 후보를 순서대로 훑어 "실제로 21 이상인" 첫 JDK 를 고른다.
#   JAVA_HOME → macOS java_home -v 21 → sdkman → Gradle toolchain(~/.gradle/jdks) → Homebrew openjdk@21 → /Library/Java
# 셰넌도어는 JDK 17 Temurin 에도 있지만 -XX:+ZGenerational 은 21 부터라 21 을 강제한다.
java_major() { "$1/bin/java" -XshowSettings:properties -version 2>&1 | awk -F'= ' '/java.specification.version/ {print $2}'; }

CANDIDATES=()
[[ -n "${JAVA_HOME:-}" ]] && CANDIDATES+=("$JAVA_HOME")
if [[ "$(uname)" == "Darwin" ]] && JH="$(/usr/libexec/java_home -v 21 2>/dev/null)"; then CANDIDATES+=("$JH"); fi
CANDIDATES+=(
  "$HOME"/.sdkman/candidates/java/21*
  "$HOME"/.gradle/jdks/*21*/Contents/Home "$HOME"/.gradle/jdks/*21*/*/Contents/Home "$HOME"/.gradle/jdks/*21*
  /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
  /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  /Library/Java/JavaVirtualMachines/*21*/Contents/Home
)
SELECTED=""
for d in "${CANDIDATES[@]}"; do
  [[ -x "$d/bin/java" ]] || continue
  if [[ "$(java_major "$d")" -ge 21 ]] 2>/dev/null; then SELECTED="$d"; break; fi
done
if [[ -z "$SELECTED" ]]; then
  echo "[run] JDK 21 을 찾지 못했습니다. 현재 JAVA_HOME=${JAVA_HOME:-<없음>}, PATH java: $(java -version 2>&1 | head -1)" >&2
  echo "[run] 후보 위치에 없다면 JAVA_HOME=/path/to/jdk-21 scripts/run.sh ... 로 직접 넘겨주세요." >&2
  echo "[run] brew 설치본: ls /opt/homebrew/opt/ | grep -i jdk  로 경로 확인" >&2
  exit 1
fi
export JAVA_HOME="$SELECTED"
JAVA_BIN="$JAVA_HOME/bin/java"
echo "[run] JDK: $JAVA_HOME" >&2

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
# macOS 기본 bash 3.2 는 set -u 에서 빈 배열 확장을 unbound 로 본다 → ${arr[@]+"${arr[@]}"} 관용구 사용
echo "$JAVA_BIN ${COMMON_OPTS[*]} $GC_OPTS -jar $JAR ${SPRING_OPTS[*]+"${SPRING_OPTS[*]}"}" > "$OUT/jvm-flags.txt"

echo "[run] collector=$COLLECTOR profile=$PROFILE heap=$HEAP -> $OUT" >&2
echo "[run] 서버가 뜨면 다른 터미널에서: k6 run load/board.js" >&2
echo "[run] 힙 덤프: scripts/dump.sh $COLLECTOR $PROFILE" >&2

# shellcheck disable=SC2086
exec "$JAVA_BIN" "${COMMON_OPTS[@]}" $GC_OPTS -jar "$JAR" ${SPRING_OPTS[@]+"${SPRING_OPTS[@]}"}
