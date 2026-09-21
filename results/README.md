# results/

`results/<collector>/<profile>/` 마다:

| 파일 | 커밋 | 내용 |
|---|---|---|
| `summary.md` | O | 실행 조건, k6 결과, gc.log 요약, 관찰. **읽을 것은 이것** |
| `machine.txt`, `java-version.txt`, `jvm-flags.txt` | O | 재현용 환경 기록 |
| `histogram-*.txt`, `threads-*.txt` | O | jcmd 클래스 히스토그램 / 스레드 덤프 |
| `gc.log` | X (gitignore) | 원본 GC 로그. `scripts/summarize-gc.sh` 로 요약 |
| `rec.jfr`, `dump-*.hprof` | X (gitignore) | JFR 녹화, 힙 덤프 (수백 MB) |
