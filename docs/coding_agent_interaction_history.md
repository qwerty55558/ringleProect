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

SSE 채널 세 개로 분리:

- `Me::Bus` (per-user) → `/me/stream` → 자기 멤버십 변화/만료
- `Admin::MembershipBus` (글로벌) → `/admin/memberships/stream` →
  누구의 멤버십이든 변화/만료. AdminPage 에서 구독.
- `Study::Bus` (글로벌) → `/study_materials/stream` →
  커리큘럼 생성/리셋 시 모든 /study 탭 갱신.

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
