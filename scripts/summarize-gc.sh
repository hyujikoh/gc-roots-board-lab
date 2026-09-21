#!/usr/bin/env bash
# gc.log 에서 정지 시간을 요약한다. (G1 / 셰넌도어 / ZGC 공통)
#
#   scripts/summarize-gc.sh results/g1/default/gc.log
#   scripts/summarize-gc.sh --all          # results/ 아래 모든 gc.log 를 표로
#
# 출력
#   1) GC 이벤트(Pause ...) 기준: 횟수, 최대/평균/총 정지(ms), 종류별 분포
#   2) safepoint 기준: 총 정지 시간과 최대 (힙 덤프·JIT 등 GC 외 정지까지 포함한 "진짜" STW)
#   3) 경고 신호: Allocation Stall(ZGC), Degenerated/Full GC(셰넌도어), Full GC·Evacuation Failure(G1)
#      셰넌도어 Pacer 지연 총량은 로그 끝의 [gc,stats] "Pacing" 항목에서 직접 확인한다.
#
# 정지 시간 추출 기준
#   - "[gc]" 또는 "[gc,phases]" 태그의 info 라인 중 "Pause <이름> ... <숫자>ms" 로 끝나는 것.
#     G1: Pause Young (Normal|Concurrent Start|Mixed|Prepare Mixed), Pause Remark, Pause Cleanup, Pause Full
#     셰넌도어: Pause Init Mark, Pause Final Mark, Pause Init Update Refs, Pause Final Update Refs, Pause Final Roots
#     ZGC: Pause Mark Start, Pause Mark End, Pause Relocate Start (세대 구분 ZGC 는 "Y:"/"O:" 접두)
#   - 같은 GC(n) 의 같은 Pause 가 [gc] 와 [gc,phases] 양쪽에 찍히면 한 번만 센다.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

summarize_one() {
  local log="$1"
  if [[ ! -s "$log" ]]; then
    echo "(비어 있음) $log"
    return
  fi
  local rel="${log#"$ROOT"/}"
  local collector profile
  collector="$(echo "$rel" | awk -F/ '{print $2}')"
  profile="$(echo "$rel" | awk -F/ '{print $3}')"

  awk -v collector="$collector" -v profile="$profile" '
    # ---------- Pause 이벤트 ----------
    /\[info\]\[gc(,phases)?[ ]*\] GC\([0-9]+\) (Y: |O: )?Pause / {
      # GC id
      match($0, /GC\([0-9]+\)/); gcid = substr($0, RSTART, RLENGTH)
      # "Pause ..." 부터 끝까지
      match($0, /(Y: |O: )?Pause .*$/); rest = substr($0, RSTART, RLENGTH)
      # 마지막 토큰이 <숫자>ms 여야 한다
      n = split(rest, tok, " ")
      last = tok[n]
      if (last !~ /^[0-9.]+ms$/) next
      ms = substr(last, 1, length(last) - 2) + 0
      # 정지 이름: 괄호 안 부제까지 포함, 힙 크기 변화(예: 100M->20M(1024M)) 와 시간은 제외
      name = rest
      sub(/ [0-9]+[KMG]?(\([0-9]+%\))?->.*$/, "", name)   # G1/셰넌도어 힙 변화
      sub(/ [0-9.]+ms$/, "", name)
      key = gcid "|" name
      if (key in seen) next
      seen[key] = 1
      cnt++; total += ms
      if (ms > max) { max = ms; maxline = rest }
      kind_cnt[name]++; kind_total[name] += ms
      if (ms > kind_max[name]) kind_max[name] = ms
      if (name ~ /^Pause Full/) full++
      if (name ~ /^Pause Degenerated GC/) degen++
    }
    # ---------- safepoint ----------
    /\[safepoint[ ]*\] Safepoint "/ {
      match($0, /Total: [0-9]+ ns/); t = substr($0, RSTART + 7, RLENGTH - 10) + 0
      sp_cnt++; sp_total += t
      if (t > sp_max) { sp_max = t; match($0, /Safepoint "[^"]+"/); sp_maxname = substr($0, RSTART + 11, RLENGTH - 12) }
    }
    # ---------- 경고 신호 ----------
    /\[gc[ ]*\] Allocation Stall/ { stall++ }
    /\[info\]\[gc[ ]*\] GC\([0-9]+\) .*\(Evacuation Failure\)/ { evacfail++ }

    END {
      printf("### %s / %s\n\n", collector, profile)
      if (cnt == 0) { print "Pause 이벤트를 찾지 못했습니다. 로그 형식을 확인하세요."; exit }
      printf("| 항목 | 값 |\n|---|---|\n")
      printf("| GC 정지 횟수 | %d |\n", cnt)
      printf("| 최대 정지(ms) | %.3f (%s) |\n", max, maxline)
      printf("| 평균 정지(ms) | %.3f |\n", total / cnt)
      printf("| 총 정지(ms) | %.1f |\n", total)
      if (sp_cnt > 0) {
        printf("| safepoint 총 시간(ms) | %.1f (%d회) |\n", sp_total / 1e6, sp_cnt)
        printf("| safepoint 최대(ms) | %.3f (%s) |\n", sp_max / 1e6, sp_maxname)
      }
      printf("| Allocation Stall | %d |\n", stall)
      printf("| Full GC | %d |\n", full)
      printf("| Degenerated GC (셰넌도어) | %d |\n", degen)
      printf("| 이주 실패 (G1 Evacuation Failure) | %d |\n", evacfail)
      printf("\n종류별\n\n| 정지 종류 | 횟수 | 최대(ms) | 평균(ms) | 총(ms) |\n|---|---|---|---|---|\n")
      for (k in kind_cnt)
        printf("| %s | %d | %.3f | %.3f | %.1f |\n", k, kind_cnt[k], kind_max[k], kind_total[k] / kind_cnt[k], kind_total[k])
      # 비교표 한 줄 (docs/02-collector-compare.md 에 붙여넣기용)
      printf("\n비교표 행: | %s | %s | (RPS) | (p99) | %d | %.2f | %.3f | %.1f | |\n\n",
             collector, profile, cnt, max, total / cnt, total)
    }
  ' "$log"
}

if [[ "${1:-}" == "--all" ]]; then
  find "$ROOT/results" -name gc.log | sort | while read -r f; do summarize_one "$f"; done
else
  summarize_one "${1:?usage: $0 <gc.log> | --all}"
fi
