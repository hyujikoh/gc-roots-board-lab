#!/usr/bin/env bash
# 실행 중인 게시판 서버의 힙 덤프와 클래스 히스토그램을 뜬다. 부하가 걸린 도중에 실행할 것.
#
#   scripts/dump.sh <collector> [profile] [tag]
#
# 결과: results/<collector>/<profile>/dump[-tag].hprof, histogram[-tag].txt, threads[-tag].txt
#
# 주의
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

PID="$("$JCMD" -l | awk '/app\.jar/ {print $1}' | head -1)"
if [[ -z "$PID" ]]; then
  echo "[dump] app.jar 프로세스를 찾지 못했습니다. 서버가 떠 있나요?" >&2
  exit 1
fi

echo "[dump] pid=$PID -> $OUT" >&2
"$JCMD" "$PID" GC.class_histogram > "$OUT/histogram$TAG.txt"
"$JCMD" "$PID" Thread.print > "$OUT/threads$TAG.txt"
# -all=false: 도달 가능한(live) 객체만. 루트 경로 분석에는 이쪽이 맞다.
"$JCMD" "$PID" GC.heap_dump -all=false "$OUT/dump$TAG.hprof"

echo "[dump] 완료. Eclipse MAT 로 $OUT/dump$TAG.hprof 를 열고" >&2
echo "       Post 클래스 → Merge Shortest Paths to GC Roots → exclude all phantom/weak/soft" >&2
echo "[dump] 히스토그램 상위 15:" >&2
head -20 "$OUT/histogram$TAG.txt" >&2
