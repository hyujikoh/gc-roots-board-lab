#!/usr/bin/env bash
# 실행 중인 게시판 서버의 힙 덤프와 클래스 히스토그램을 뜬다. 부하가 걸린 도중에 실행할 것.
#
#   scripts/dump.sh <collector> [profile] [tag]
#
# 결과: results/<collector>/<profile>/dump[-tag].hprof, histogram[-tag].txt, threads[-tag].txt
#
# 주의
# - jcmd 의 GC.class_histogram 과 GC.heap_dump 는 기본(-all=false)이면 먼저 Full GC 를 강제한다
#   (gc.log 에 "Pause Full (Heap Inspection Initiated GC)" / "(Heap Dump Initiated GC)" 로 찍힘). 이 정지가 컬렉터 비교를 오염시키므로
#   여기서는 -all=true 로 떠서 Full GC 없이 덤프한다. 덤프에 쓰레기 객체가 섞이지만 MAT 는 파싱 때 도달 불가 객체를 걸러내므로
#   루트 경로 분석에는 지장이 없다 (히스토그램은 "쓰레기 포함" 수치임을 감안).
# - 힙 덤프는 STW 로 수 초 멈춘다. 같은 실행의 gc.log 로 정지 시간을 비교할 때는
#   덤프 시각(safepoint 로그의 "GC.heap_dump" 또는 HeapDumper) 근처를 빼고 봐야 한다.
#   그래서 컬렉터 비교(02) 실행과 루트 지도(01/03) 실행은 분리해서 하는 것을 권한다.
# - hprof 는 힙 크기만큼 크다(1GB 힙이면 수백 MB). .gitignore 에 걸려 있다.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${1:?usage: $0 <collector> [profile] [tag]}"
PROFILE="${2:-default}"
TAG="${3:+-$3}"
OUT="$ROOT/results/$COLLECTOR/$PROFILE"
JCMD="${JAVA_HOME:+$JAVA_HOME/bin/}jcmd"
mkdir -p "$OUT"

# 컨테이너(run-docker.sh, 이름 gc-lab)가 떠 있으면 그 안에서 jcmd 를 돌린다. 덤프 파일은 마운트된 results/ 로 바로 떨어진다.
if command -v docker >/dev/null 2>&1 && [[ -n "$(docker ps -q -f name='^gc-lab$' 2>/dev/null)" ]]; then
  OUT_CTR="/lab/results/$COLLECTOR/$PROFILE"
  PID="$(docker exec gc-lab jcmd -l | awk '/app\.jar/ {print $1}' | head -1)"
  [[ -n "$PID" ]] || { echo "[dump] 컨테이너 안에서 app.jar 프로세스를 찾지 못했습니다." >&2; exit 1; }
  echo "[dump] (docker gc-lab) pid=$PID -> $OUT" >&2
  docker exec gc-lab jcmd "$PID" GC.class_histogram -all > "$OUT/histogram$TAG.txt"
  docker exec gc-lab jcmd "$PID" Thread.print > "$OUT/threads$TAG.txt"
  docker exec gc-lab jcmd "$PID" GC.heap_dump -all=true "$OUT_CTR/dump$TAG.hprof"
else
  PID="$("$JCMD" -l | awk '/app\.jar/ {print $1}' | head -1)"
  if [[ -z "$PID" ]]; then
    echo "[dump] app.jar 프로세스를 찾지 못했습니다. 서버가 떠 있나요? (컨테이너라면 이름이 gc-lab 이어야 합니다)" >&2
    exit 1
  fi
  echo "[dump] pid=$PID -> $OUT" >&2
  "$JCMD" "$PID" GC.class_histogram -all > "$OUT/histogram$TAG.txt"
  "$JCMD" "$PID" Thread.print > "$OUT/threads$TAG.txt"
  "$JCMD" "$PID" GC.heap_dump -all=true "$OUT/dump$TAG.hprof"
fi

echo "[dump] 완료. Eclipse MAT 로 $OUT/dump$TAG.hprof 를 열고" >&2
echo "       Post 클래스 → Merge Shortest Paths to GC Roots → exclude all phantom/weak/soft" >&2
echo "[dump] 히스토그램 상위 15:" >&2
head -20 "$OUT/histogram$TAG.txt" >&2
