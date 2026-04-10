# AI 코딩 툴 사용 기록 (Coding Agent Interaction History)

이 문서는 과제 PDF 의 제출 요건 #3 ("AI 기반 개발 툴 사용 기록") 을 충족하기
위한 자료입니다. 본 프로젝트는 처음부터 끝까지 **Claude Code (Anthropic, claude-opus-4-6 with 1M context)**
를 메인 페어 프로그래머로 활용했습니다. 아래는 ① 어떤 방식으로 prompt 를
구성했는지, ② 모델이 출력한 코드를 어떻게 검토/수정/검증했는지, ③ 결과물
사용 예시 입니다.

> **스크린샷**: 본 디렉토리의 `screenshots/` 폴더에 첨부합니다 (수동 캡쳐 필요).
> 아래 본문에서 `[SCREENSHOT: ...]` 마커 위치에 해당 이미지를 삽입해주세요.

---

## 1. 작업 환경

| 항목                  | 값                                                                                  |
| --------------------- | ----------------------------------------------------------------------------------- |
| 메인 에이전트         | Claude Code (CLI), Opus 4.6 (1M context)                                            |
| 보조 도구             | -                                                                                   |
| Operating system      | macOS Darwin 25.4.0                                                                 |
| Repo 작업 모드        | 단일 git 워크트리, develop 브랜치                                                   |
| 외부 통신             | Gemini API, ElevenLabs API (실제 호출, mock 아님)                                   |
| 작업 분량 (대략)      | Backend ~25 파일 (모델/서비스/컨트롤러/스펙) + Frontend ~20 파일 + 문서             |

`[SCREENSHOT: claude_code_session.png — Claude Code CLI 가 띄워진 터미널 화면]`

---

## 2. Prompt 전략

### 2-1. 영속 메모리 + CLAUDE.md 로 컨텍스트 자동 주입

매 세션마다 동일한 컨벤션을 다시 설명하지 않도록 다음 두 가지를 사용했습니다:

1. **`CLAUDE.md`** (repo 최상단): 프로젝트 원칙 (Rails / TS+React / persistent
   storage / extensibility / review-grade / 테스트 필수) + 컨벤션 파일 경로 +
   디렉토리 검색 스코핑 규칙. Claude Code 가 매 turn 마다 자동 주입.
2. **`.claude/projects/.../memory/`** (Claude Code 의 auto memory): 과제 PDF
   요약, 진행 상황 스냅샷, 사용자 피드백 기록. 새 세션 시작 시 Claude 가 알아서
   읽어들임.

`[SCREENSHOT: claude_md.png — CLAUDE.md 와 메모리 디렉토리 구조]`

### 2-2. "전체 다 해줘" 보다 "왜 / 어떻게" 를 한 줄씩

큰 변경일수록 prompt 를 다음과 같은 한 줄짜리 의도 + 제약 으로 끊었습니다:

```
컨벤션 읽고 프론트엔드 재구성 ㄱㄱ
```
```
docs 에 풀스택 과제 읽고 지금 구현안된 거 있나 제대로 체크해봐
```
```
대화내용을 영속화 시키는 게 낫잖아 명시적 삭제 이전까지 캐싱해놓고 계속해서
들을 수 있게 해줘야지 그리고 유저 결제 api 시뮬도 해야됨 mock object 호출해서
pg사 결제 시뮬레이션 가능하게
```

이렇게 짧은 프롬프트가 가능했던 이유는 사전 컨텍스트(PDF 요약, 컨벤션, 메모리)
가 이미 모델 head 안에 들어 있었기 때문입니다. 모델이 스스로 ToolSearch / Read /
Glob / Grep 으로 필요한 파일을 좁혀 읽고, 영향 범위를 보고서 형태로 제시한 뒤
편집을 진행하도록 흐름을 잡았습니다.

`[SCREENSHOT: prompt_short.png — 짧은 prompt 이지만 모델이 풍부한 plan 으로 응답하는 화면]`

### 2-3. 의사결정 분기는 옵션 표로 받아내기

요구사항이 모호하거나 트레이드오프가 있을 때는 "옵션 A/B/C 를 표로 비교해서
보여줘. 결정해주면 그대로 진행해" 라는 패턴으로 모델에게 결정 보조 자료를
받아냈습니다. 예: "static API key vs JWT vs 현행 stub" 비교, "옵션 A: TTS 캐시만 /
옵션 B: 메시지 영속화까지" 비교. 사람이 결정하고 모델이 실행.

`[SCREENSHOT: options_table.png — 모델이 옵션을 ASCII 박스 표로 출력한 화면]`

### 2-4. 사용자 피드백을 즉시 메모리/CLAUDE.md 로 영속화

세션 도중에 받은 지시는 즉시 영속화했습니다. 예:

> "프론트엔드 관련은 frontend 디렉토리로 스코프 좁혀서 검색하라고 하고 백엔드
> 관련은 backend 디렉토리로 스코프 좁혀달라고 하셈 명시적인 명령 없이는 바로
> 스캔뜨지 말라고 (토큰 아끼기)"

이 한 줄을 받자마자 `CLAUDE.md` 의 "Search scoping (token discipline)" 섹션으로
영속화했고, 이후 모든 검색이 한 디렉토리에 좁혀집니다. 메모리의 "feedback" 타입은
이런 즉시 학습을 위해 존재합니다.

`[SCREENSHOT: claude_md_scoping.png — CLAUDE.md 에 scoping 규칙이 추가된 diff]`

---

## 3. Output 검토 / 수정 / 검증 루프

### 3-1. 컴파일/테스트 자동화로 hallucination 차단

LLM 이 만든 모든 코드 변경은 다음 두 단계를 거쳐야 "끝" 으로 처리했습니다.

| 영역    | 검증 명령                                                              |
| ------- | ---------------------------------------------------------------------- |
| Backend | `bundle exec rspec` → 89 examples 전부 통과해야 commit 진행            |
| Frontend| `pnpm exec tsc --noEmit && pnpm exec vitest run` → tsc + 12 tests pass |

테스트가 깨지면 모델이 실패 메시지를 받고 root cause 분석 → 수정 → 재실행 합니다.
예시:

```
1) POST /api/v1/ai/speech returns mp3 bytes from ElevenLabs
   WebMock::NetConnectNotAllowedError:
     Real HTTP connections are disabled. Unregistered request:
     GET https://api.elevenlabs.io/v1/voices
```

→ 모델이 즉시 원인 인식: `Tts::Synthesize` 가 새로 `voice_id` lookup 을 호출하므로
기존 spec 의 `synthesize` stub 만으로는 부족. spec 에 `voice_id` stub 추가하고
재실행 → green.

`[SCREENSHOT: rspec_red_to_green.png — 실패 → 수정 → 통과 sequence]`

### 3-2. 컨벤션 위반 자동 점검

`Convention.md` 에 명시된 규칙 (예: 인라인 `style={{...}}` 금지, 단일 `global.css`)
을 위반하지 않는지 매 변경 후에 `Grep -r "style=\\{\\{"` 같은 직접 검색으로 확인.
유일하게 남은 인라인 스타일은 의도적으로 동적인 waveform bar height 한 곳입니다.

```
src/global.css:5: * `className` only — no inline `style={{ ... }}` props except for values
src/pages/ConversationPage.tsx:243:        <div key={i} className="bar" style={{ height: `${v}px` }} />
```

`[SCREENSHOT: convention_grep.png — 컨벤션 위반 검색 결과가 비어있는 화면]`

### 3-3. 사람이 직접 읽고 받아들이는 patch review

모든 파일 편집은 Claude Code 의 Edit/Write tool 을 통해 diff 형태로 표시되고,
사용자가 승인 / 거부 합니다. "옳아 보이지만 의도와 다른" 변경은 그 자리에서
거부하거나 prompt 로 정정 지시했습니다.

`[SCREENSHOT: edit_tool_diff.png — Claude Code 의 Edit tool diff 승인 화면]`

### 3-4. 한 turn = 한 책임

단일 turn 에 너무 많은 파일을 한꺼번에 만들지 않도록 의식적으로 끊었습니다.
예시:

```
turn 1: 마이그레이션 4종 작성
turn 2: 모델 3종 작성
turn 3: 서비스 + 컨트롤러
turn 4: 라우트 + 기존 컨트롤러 패치
turn 5: 스펙 작성
turn 6: rspec 돌리고 fail 4건 fix
```

이렇게 끊으면 (1) 사람이 검토하기 쉽고 (2) 실패가 발생해도 어느 turn 에서
문제가 났는지 즉시 알 수 있습니다.

---

## 4. 결과물 사용 예시

### 4-1. 홈 → 멤버십 구매 (PG mock)

홈 페이지에 "테스트 카드" 셀렉터가 노출됩니다. 아래 5종 토큰 중 하나를 골라
"구매하기" 를 누르면 백엔드의 `PaymentGateway` mock 이 토큰 별로 다른 응답을
돌려줍니다.

| 토큰                    | UI 라벨           | 결과                       |
| ----------------------- | ----------------- | -------------------------- |
| `tok_visa`              | 정상 카드 (Visa)  | 멤버십 row 추가            |
| `tok_visa_declined`     | 거절된 카드       | "결제 실패: 카드가 거절..."|
| `tok_insufficient`      | 한도 초과         | "결제 실패: 한도 초과..."   |
| `tok_processing_error`  | PG 일시 오류      | "PG 서버가 일시적으로..."   |

`[SCREENSHOT: home_test_cards.png — 카드 셀렉터 + 거절 시 에러 banner]`

### 4-2. 대화 페이지 → STT → SSE → TTS

마이크 클릭 → waveform → 답변 완료 → STT 텍스트 즉시 표시 → LLM 토큰 스트리밍 +
문장 단위 TTS 병렬 → AudioQueue 가 도착 순서 보장하며 재생.

`[SCREENSHOT: conversation_streaming.png — 응답 텍스트가 스트리밍되는 도중 첫 음성이 재생되는 모습]`

### 4-3. 새로고침 후 영속화 검증

대화 한 두 turn 진행 → 브라우저 새로고침 → 모든 메시지 + ▶ 버튼 그대로 → ▶ 클릭
→ 음성 재생. 네트워크 탭에서 ElevenLabs 호출이 0건임을 확인 (서버 disk 캐시 hit).

`[SCREENSHOT: persistence_after_reload.png — 새로고침 후 동일한 thread + ▶ 재생 로그]`

### 4-4. 명시적 대화 삭제

우측 하단 🛠 dev panel → "현재 대화 삭제" → DELETE /api/v1/conversations/:id →
모든 메시지 + 첨부 blob 까지 cascade 삭제.

`[SCREENSHOT: dev_panel_delete.png — dev panel 의 삭제 버튼 + 확인 dialog]`

### 4-5. 백엔드 RSpec 결과

```
$ bundle exec rspec
.........................................................................................

Finished in 0.45993 seconds (files took 1.09 seconds to load)
89 examples, 0 failures
```

`[SCREENSHOT: rspec_green.png — 89 examples, 0 failures 출력]`

### 4-6. 프론트엔드 Vitest 결과

```
$ pnpm exec vitest run
 RUN  v4.1.3 .../frontend

 Test Files  4 passed (4)
      Tests  12 passed (12)
```

`[SCREENSHOT: vitest_green.png — 12 tests passed 출력]`

---

## 5. 회고

### 5-1. 잘 먹힌 것

- **메모리 + CLAUDE.md** 조합 덕에 새 세션에서도 prompt 가 짧게 유지되었고
  컨벤션 위반이 거의 발생하지 않았습니다.
- **검증 루프 자동화**가 제일 결정적이었습니다. 컴파일/테스트 명령이 실패를
  먹잇감으로 던져주면 모델이 root cause 까지 찾아가는 흐름이 매끄럽습니다.
- **옵션 표로 의사결정 보조** 패턴은 사람이 집중할 곳을 좁혀줘서 큰 분기점
  (영속화 vs 인메모리, JWT vs stub) 에서 시간을 아꼈습니다.

### 5-2. 잘 안 된 / 주의해야 할 것

- **메모리가 stale 해지는 위험**: 한 번은 메모리에 "README + interaction history
  완료" 라고 적혀 있었지만 실제 README.md 는 0 바이트였습니다. 이후로는 메모리
  업데이트 전에 실제 파일 상태를 verify 하는 흐름을 정착시켰습니다.
- **자율 scan 토큰 낭비**: 명시적 명령 없이 모델이 양쪽 디렉토리를 다 훑는
  일이 있었습니다. CLAUDE.md 에 디렉토리 스코핑 룰을 추가해 해결.
- **PDF 요구사항 누락 catch**: "유저 본인 발화 재생 버튼" 누락은 PDF 를 다시
  훑기 전까지 모르고 지나갔습니다. 자동 체크리스트 만들어두면 좋겠다는 교훈.

### 5-3. 다음에 더 해보고 싶은 것

- pre-commit hook 으로 rspec/vitest 자동 실행
- PDF 요구사항을 미리 체크리스트로 변환 → 매 세션 시작 시 모델이 자동 점검
- TTS 캐시 hit ratio 모니터링 대시보드 (X-Tts-Cache 헤더 기반)

---

## 6. 후속 결정 — 폴링 → SSE → Falcon 마이그레이션

리뷰 직전에 "ConversationPage 가 30초짜리 테스트 멤버십 만료를 즉시 감지하려면
어떻게 하나" 라는 요구사항이 더 명확해지면서, 초기 폴링 4초 구현을 두 단계에
걸쳐 갈아엎었습니다. 결정 흐름을 코딩 에이전트와 함께 추적한 기록입니다.

### 6-1. 폴링 → SSE 푸시

폴링은 (a) 만료 감지가 최대 4초 지연 (b) 사용자가 머무는 동안 끊임없이 GET
호출이 발생한다는 두 가지 문제가 있었습니다. 모델이 제안한 대안 비교:

```
┌──────────────────┬─────────────────────┬──────────────────────────┐
│ 옵션             │ 만료 감지 지연       │ idle 부하                │
├──────────────────┼─────────────────────┼──────────────────────────┤
│ 폴링 4s          │ 0 ~ 4s              │ 4s 마다 GET /me          │
│ 폴링 1s          │ 0 ~ 1s              │ 1s 마다 GET /me          │
│ SSE (Bus 푸시)   │ 100ms 미만          │ 0 (idle 시 fiber 대기)   │
└──────────────────┴─────────────────────┴──────────────────────────┘
```

SSE 채널 네 개로 분리:

- `Me::Bus` (per-user) → `/me/stream` → 자기 멤버십 변화/만료
- `Admin::MembershipBus` (글로벌) → `/admin/memberships/stream` →
  누구의 멤버십이든 변화/만료. AdminPage 에서 구독.
- `Study::Bus` (글로벌) → `/study_materials/stream` →
  커리큘럼 생성/리셋 시 모든 /study 탭 갱신.
- `AnalysisBus` (per-user) → `/analysis/stream` →
  분석 완료/실패 시 AnalysisPage 에서 구독.

`Membership` 모델의 `after_commit` 콜백이 두 버스 모두에 publish. 시간 기반
만료는 row mutation 이 없어서 콜백을 안 타기 때문에, SSE 컨트롤러가
`Queue#pop(timeout: 다음_만료까지)` 로 정확히 그 시점에 깨어나서 같은 코드
경로로 들어갑니다.

### 6-2. Puma 의 한계 발견

SSE 구현 후 첫 회귀 테스트에서 모델이 즉시 짚어준 문제: **Puma + SSE 는
새로고침 폭주에 취약**합니다. SSE 1 연결이 1 OS 스레드를 점유하는데,
`Queue#pop(timeout:)` 안에서 자고 있는 스레드는 클라이언트가 끊어도 다음
write 시도 시점까지 그 사실을 모릅니다. 워커 풀(기본 3 스레드)이 zombie 로
가득 차면 일반 REST 까지 hang.

처음에는 heartbeat 를 15s → 2s 로 줄이고 Puma threads_count 를 16 으로
올려서 *완화* 했지만, 본질적인 해결이 아니라는 게 모델과 사람의 합의.

### 6-3. Falcon (fiber 기반) 으로 전환

Java Virtual Thread 와 정확히 동등한 Ruby 의 대응이 Fiber 라는 점을 사람이
공유했고, 모델이 Rails 7.2 + Falcon + `isolation_level: :fiber` 조합으로
전환을 진행했습니다.

```
┌──────────────────────┬─────────────────────┬──────────────────────────┐
│ 항목                 │ Puma                │ Falcon                   │
├──────────────────────┼─────────────────────┼──────────────────────────┤
│ 동시성 단위          │ OS 스레드 (~1MB)    │ Fiber (~수 KB)           │
│ Close 감지           │ 다음 write 시도 시  │ 이벤트 루프 즉시 (μs)    │
│ SSE 1000 conn 비용   │ ~1GB → OOM          │ ~몇 MB                   │
│ Heartbeat 의도       │ Zombie cleanup      │ proxy/browser keepalive  │
│ 우리 heartbeat 값    │ 2s (panic mode)     │ 30s (정상)               │
└──────────────────────┴─────────────────────┴──────────────────────────┘
```

설정은 세 곳:
- `backend/Gemfile` — `gem 'falcon'`, `gem 'async-http'`
- `backend/config/environments/{development,production}.rb` —
  `isolation_level = :fiber`, `async_query_executor = :global_thread_pool`
- `backend/config/database.yml` — SQLite WAL 활성화 + pool 32

### 6-4. Falcon 도 끝은 아니다 — 자원 보호 레이어

사람이 또 한 번 더 짚었습니다: "비동기로 해도 새로고침 몇천 번 하면 결국
fiber 가 누적되지 않냐". 정답이라 두 층 추가:

1. `config/initializers/rack_attack.rb` — SSE 신규 오픈 per-user 분당 30,
   per-IP 분당 60. 그 이상은 즉시 429.
2. `Me::Bus::MAX_PER_USER = 8` — 동시 구독 절대 캡. subscribe 에서
   `TooManySubscribersError` raise → 컨트롤러가 catch 해서
   `event: error too_many_connections` 푸시 후 종료.

`spec/requests/sse_throttling_spec.rb` 4 examples 로 검증.

### 6-5. Production scale-out 단계별 경로

리뷰 시 "그 다음 단계는?" 질문에 답할 수 있도록 README 에 계단 도식을
적어 두었습니다:

```
┌────────────────┬─────────────────────────────────────────────────────┐
│ Phase          │ 무엇을 바꾸는가                                     │
├────────────────┼─────────────────────────────────────────────────────┤
│ 0 (현재)       │ Falcon + sqlite + in-process Bus                    │
│ 1 (production) │ DB adapter sqlite → pg, async_query_executor 그대로 │
│ 2 (multi-node) │ in-process Bus → Redis Pub/Sub                      │
│ 3 (10k+ SSE)   │ Nginx → SSE Gateway (Node/Go) → Redis → Rails API   │
└────────────────┴─────────────────────────────────────────────────────┘
```

Phase 0 → 1 은 database.yml 한 줄, 1 → 2 는 Bus 모듈 한 파일을 Redis 어댑터로
교체하면 됩니다. 3 단계는 동시 SSE 가 단일 머신 한계(보통 10k+) 에 부딪힐
때만 의미 있습니다.

### 6-6. 이 라운드에서 모델이 잘한 것 / 못한 것

**잘한 것**
- 사용자 한 마디("새로고침 몇천 번 하면?") 에 대해 fiber 누적 시나리오를
  스스로 그려서 두 층 방어를 즉시 제안 — rate limit + bus cap.
- 작업을 배치로 묶지 않고 단계마다 spec 으로 검증한 뒤 다음으로 넘어갔습니다.
  Puma → Falcon 같은 큰 변경에서도 회귀 0 건.
- 모든 새 SSE 코드에 *왜 이렇게 했는지* 주석을 박았습니다 (특히 fiber 별
  isolation 이유). 다음 사람이 같은 함정에 다시 빠지는 걸 막는 패턴.

**못한 것**
- 폴링 4s 구현 당시에 "SSE 가 더 옳다" 는 분석을 미리 못 했습니다 — 사용자가
  요구사항을 한 번 더 강조하기 전까지 폴링을 유지하려는 관성이 보였습니다.
- Falcon 전환 직후에도 SSE 컨트롤러의 `response.stream.closed?` 폴링 체크가
  남아 있었고, fiber 환경에서 의미가 줄어든 걸 사람이 한 번 더 지적해야
  정리됐습니다.

---

## 7. 배포 인프라 구축 + 프로덕션 이슈 해결

### 7-1. Docker + Nginx + GitHub Actions CI/CD

배포 서버에 Docker Compose 기반 인프라를 세팅했습니다.

```
┌─────────────────────────────────────────────────┐
│ Nginx (호스트)                                    │
│  ├─ ringle.clauminirockpt.me → ringle-frontend  │
│  └─ ringleapi.clauminirockpt.me → ringle-backend│
│                                                   │
│  ┌── Docker (ringle-network) ──────────────────┐ │
│  │ ringle-frontend (nginx:alpine)  :80         │ │
│  │ ringle-backend  (Rails+Falcon)  :3000       │ │
│  │ ringle-db       (postgres:16)   :5432       │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

GitHub Actions 워크플로우가 `main`/`develop` push 시 자동 빌드 → GHCR 이미지 push.
프론트엔드 `VITE_API_BASE_URL`은 GitHub Repository Secret으로 빌드 타임에 주입.

### 7-2. 프로덕션 이슈 진단 흐름

배포 후 발견된 이슈를 모델과 함께 하나씩 진단한 기록:

```
┌───────────────────────────┬───────────────────────────────────────────┐
│ 이슈                       │ 원인 → 해결                               │
├───────────────────────────┼───────────────────────────────────────────┤
│ URL 파싱 에러              │ VITE_API_BASE_URL 빈 문자열 → Repo Secret │
│                           │ 에서 Environment Secret으로 잘못 설정      │
│ 502 Bad Gateway           │ Nginx upstream이 127.0.0.1 → Docker 컨테  │
│                           │ 이너 이름으로 변경                         │
│ 301 리다이렉트 루프        │ Rails force_ssl + assume_ssl 미설정 →     │
│                           │ config.assume_ssl = true 추가              │
│ CORS 에러                 │ Nginx API server block 누락 → 추가         │
└───────────────────────────┴───────────────────────────────────────────┘
```

이 중 가장 까다로웠던 것은 **Environment Secret vs Repository Secret** 차이. GitHub
Actions에서 `environment:` 지시자 없이 Environment Secret을 참조하면 빈 문자열이
주입되는데, 이 에러는 빌드 로그에서 마스킹되어 보이지 않았습니다.

`[SCREENSHOT: deploy_502_fix.png — 502 에러 진단 과정]`

---

## 8. AI 분석 기능 (Analysis) 구현

과제 PDF의 세 번째 핵심 기능 — "AI와 나눈 대화를 토대로 레벨을 분석해주는
분석 기능" 을 구현한 과정입니다.

### 8-1. Plan 모드에서 설계

Claude Code의 Plan 모드를 사용해서 기존 코드 탐색 → 설계 → 사용자 승인 → 구현
순서로 진행했습니다. 모델이 자율적으로 탐색한 결과를 바탕으로:

- 기존 SSE 패턴 (`MessagesController`, `Me::Bus`)
- 기존 서비스 패턴 (`Conversations::Summarize`)
- 프론트 쿼리 패턴 (`useMe`, `useStudyMaterials`)

을 파악하고, 동일한 아키텍처 위에 분석 기능을 얹는 방향으로 결정했습니다.

### 8-2. 백엔드 구현

```
┌─────────────────────────┬─────────────────────────────────────────────┐
│ 파일                     │ 역할                                        │
├─────────────────────────┼─────────────────────────────────────────────┤
│ Analysis (모델)          │ status(pending/completed/failed) + result   │
│ Conversations::Analyze  │ Gemini 프롬프트 구성 + 모델 체인 fallback    │
│ AnalysisController      │ GET (저장된 결과) / POST (비동기 분석 요청)   │
│ AnalysisStreamController│ SSE push — 분석 완료 시 프론트 알림           │
│ AnalysisBus             │ in-process pub/sub (Me::Bus 와 동일 패턴)    │
└─────────────────────────┴─────────────────────────────────────────────┘
```

분석은 **비동기 처리**: POST가 pending 레코드를 만들고 즉시 202 응답 → 백그라운드
Thread에서 Gemini 호출 → 완료 시 DB 저장 + AnalysisBus.publish → 프론트 SSE 수신.

프롬프트는 한국어 응답을 지시하며, 분석 항목은:
종합 레벨, 문법(점수+오류교정), 어휘(점수+대체표현), 유창성, 주제 관련성,
핵심 표현 활용도, 개선 제안.

### 8-3. 프론트엔드 구현

`AnalysisPage.tsx`는 사이드바(대화 목록) + 상세 패널(분석 결과) 구조.
상태 머신: `idle → polling → done | error`.

`useAnalysisStream` 훅이 `/analysis/stream` SSE를 구독하고, `changed` 이벤트
수신 시 GET으로 결과를 fetch합니다. 화면 이탈 후 복귀해도 pending 상태를
감지하여 SSE 대기 → 완료 즉시 결과 표시.

`[SCREENSHOT: analysis_result.png — 분석 결과 화면 (레벨 뱃지 + 점수 바 + 문법 테이블)]`

### 8-4. 사용자 피드백으로 개선된 것

이번 라운드에서 사용자 피드백으로 변경된 사항:

- "분석 내용도 저장되나?" → `analyses` 테이블 추가, 결과 영속화
- "비동기로 하라니까" → SSE 스트리밍 → POST 즉시 응답 + Thread 백그라운드 실행
- "SSE로 하셈, polling 말고" → AnalysisBus + SSE stream 추가
- "한글로 해주셈" → 프롬프트 한국어 응답 지시
- "쿨다운 5분은 너무 김" → 30초로 변경
- "devtools에 분석 초기화 넣어줘" → admin DELETE /analyses 엔드포인트 추가

---

## 9. Gemini 모델 체인 전면 업데이트

### 9-1. 무료 할당량 문제

Gemini 무료 티어의 RPD(일일 요청 수)가 모델당 20회로 제한되어 있어서, 단일
모델 사용 시 데모 도중 429 에러가 빈번했습니다.

### 9-2. 6-model fallback 체인

v1beta API에서 사용 가능한 모델을 전수 조사(`ListModels` API 호출)하여
품질 내림차순 + RPD 넉넉한 순서로 체인을 구성했습니다:

```
┌───────────────────────────┬─────┬────────┐
│ 모델                       │ RPM │ RPD    │
├───────────────────────────┼─────┼────────┤
│ gemini-3.1-flash-lite-prev│ 15  │ 500    │
│ gemini-3-flash-preview    │ 5   │ 20     │
│ gemini-2.5-flash          │ 5   │ 20     │
│ gemini-2.5-flash-lite     │ 10  │ 20     │
│ gemini-2.0-flash          │ --  │ --     │
│ gemini-2.0-flash-lite     │ --  │ --     │
└───────────────────────────┴─────┴────────┘
```

STT용 체인은 오디오 입력을 지원하는 모델만 (`gemini-3.1-flash-lite-preview`의
Live API 미지원으로 제외).

### 9-3. 전체 적용

Gemini를 사용하는 **모든 곳**에 체인을 적용했습니다:

```
┌───────────────────────────┬────────────────┐
│ 위치                       │ 체인            │
├───────────────────────────┼────────────────┤
│ MessagesController (대화) │ MODEL_CHAIN    │
│ Conversations::Analyze    │ MODEL_CHAIN    │
│ Conversations::Summarize  │ MODEL_CHAIN    │
│ StudyMaterials::Generate  │ MODEL_CHAIN    │
│ GeminiClient#transcribe   │ STT_MODEL_CHAIN│
└───────────────────────────┴────────────────┘
```

`[SCREENSHOT: model_chain_fallback.png — 서버 로그에서 429 → 다음 모델 fallback 로그]`

---

## 10. 대화 관리 / UX 개선

### 10-1. 대화 초기화 = 소프트 리셋

"대화 초기화" 버튼은 DB에서 대화를 삭제하지 않고 로컬 매핑만 해제합니다
(소프트 리셋). 분석 탭에서 과거 대화 기록이 유지됩니다. 하드 리셋(DB 삭제)은
DevTools에서만 가능합니다.

### 10-2. 커리큘럼 대화 흐름 정비

학습 탭에서 "AI 와 대화로 학습 시작" 버튼 클릭 시:

1. 기존 대화 있으면 confirm → 로컬 매핑 해제
2. `createConversation({ title, studyMaterialId })` → DB에 대화방 생성 + study_material_id 저장
3. 커리큘럼 첫 질문을 assistant 메시지로 DB에 저장 (TTS audio 포함)
4. `/conversation?study=X` 로 이동
5. ConversationPage: savedId → DB 조회 → 메시지 로드 + 첫 메시지 자동 재생

`study_material_id`가 conversation에 저장되므로, 탭 이동 후 돌아와도 AI 응답에
커리큘럼 문맥(`scenario_prompt` + `key_expressions` + `example_dialogue`)이
자동 포함됩니다.

### 10-3. TTS 음질 개선

ElevenLabs 호출 전에 텍스트를 전처리합니다:
- `___` (빈칸 placeholder) → `something` 으로 치환 (백엔드 `sanitize_for_tts`)
- `stability: 0.80`, `similarity_boost: 0.70`, `style: 0.15` 로 자연스러운 톤

### 10-4. AudioQueue 싱글톤

`AudioQueue.shared()` 로 앱 전체에서 하나의 오디오만 재생되게 변경.
학습 탭에서 재생 중에 대화 탭으로 이동하면 이전 재생이 자동 중단됩니다.

### 10-5. 서버 시간 동기화

`/me` 응답에 `server_time` 필드를 추가하고, 프론트에서 서버-클라이언트 시계
차이를 계산합니다. 모든 날짜 표시는 `VITE_TZ_OFFSET` 환경변수 기반으로
offset 적용 (기본값 UTC, 배포 시 `+9` 설정 가능).

`[SCREENSHOT: server_time_sync.png — 분석 결과의 시간 표시]`

---

## 11. StrictMode 대응

React 18 StrictMode는 개발 환경에서 effect를 2번 실행합니다. 이로 인해:

- TTS 보이스가 2번 재생
- API 호출이 2번 발생
- 상태가 꼬여서 "Loading conversation" 무한 표시

해결 패턴: `cancelled` 플래그를 effect cleanup에서 세팅.

```typescript
useEffect(() => {
  let cancelled = false
  const init = async () => {
    const data = await fetchData()
    if (cancelled) return    // StrictMode 2차 실행 시 여기서 중단
    setState(data)
  }
  void init()
  return () => { cancelled = true }
}, [deps])
```

이 패턴을 ConversationPage 초기화에 적용해서 모든 StrictMode 이슈를 해결했습니다.

---

## 12. 최종 테스트 결과

```
$ bundle exec rspec
246 examples, 0 failures

$ pnpm exec vitest run
 Test Files  6 passed (6)
      Tests  18 passed (18)
```

`[SCREENSHOT: final_tests.png — 전체 테스트 통과 출력]`
