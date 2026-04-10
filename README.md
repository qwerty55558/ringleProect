# Ringle AI Tutor — 풀스택 과제

링글 Tech팀 풀스택 채용 과제 구현물입니다. AI 영어 튜터 앱: 멤버십 구매/관리 + AI 음성 대화.

> **과제 PDF**: `docs/링글_Tech팀 풀스텍_과제.pdf`

---

## 1. 실행 방법

### 1-1. 필수 도구

| 도구            | 버전                       | 비고                              |
| --------------- | -------------------------- | --------------------------------- |
| Ruby            | 3.3.x (`backend/.ruby-version` 참조) | rbenv / asdf 권장          |
| Node.js         | 20.x 이상                  |                                   |
| pnpm            | 9.x 이상                   | `corepack enable` 또는 `npm i -g pnpm` |
| SQLite          | 3.x                        | macOS/Linux 기본 설치             |

### 1-2. 환경 변수

```bash
cp backend/.env.example backend/.env
```

`.env` 안의 두 키를 채워 넣습니다:

| 키                  | 발급처                                                        | 용도                                   |
| ------------------- | ------------------------------------------------------------- | -------------------------------------- |
| `GEMINI_API_KEY`    | https://aistudio.google.com/app/apikey                        | LLM (gemini-2.5-flash) + STT           |
| `ELEVENLABS_API_KEY`| https://elevenlabs.io 의 Profile → API key (10K chars/월 무료)| TTS                                    |
| `FRONTEND_ORIGIN`   | (선택) 기본값 `http://localhost:5173`                         | rack-cors 화이트리스트                 |

### 1-3. Backend (Rails API)

```bash
cd backend
bundle install
bin/rails db:setup            # 마이그레이션 + seeds (admin/user 3명 + plan 2종 + 커리큘럼 20개 + STT fixture 8개)
bin/rails s -p 3000           # http://localhost:3000
```

### 1-4. Frontend (React + Vite)

```bash
cd frontend
pnpm install
pnpm dev                      # http://localhost:5173
```

`.env` 가 채워졌다면 그대로 동작합니다. Backend 도메인을 다른 곳에 띄웠다면
`VITE_API_BASE_URL=https://...` 환경변수로 덮어씌울 수 있습니다.

### 1-5. 데모 시나리오

1. http://localhost:5173 접속 → 우측 하단 floating 🛠 패널에서 **계정 전환**
   (기본 계정: `Ringle Admin`, `Danny Learner`, `Alex Newcomer`)
2. **홈 페이지**: "테스트 카드" 셀렉터에서 카드를 고르고 플랜 구매
   - `tok_visa` / `tok_mastercard` → 정상
   - `tok_visa_declined` → 402 거절
   - `tok_insufficient` → 402 한도초과
   - `tok_processing_error` → 502 PG 일시 오류
3. **대화 페이지**: Talk 기능 멤버십이 있으면 진입 가능. 마이크 → 답변 완료 → 스트리밍 응답
4. 새로고침해도 대화 히스토리와 음성 재생이 그대로 살아있는지 확인 (영속화)
5. Dev 패널 → "현재 대화 삭제" 로 명시적 삭제

---

## 2. 설계 / 기술 스택 선정 배경

### 2-1. 스택

| 영역    | 선택                                                             | 이유                                                                                  |
| ------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Backend | **Rails 7.2 (API only) + Falcon (fiber 기반 async)**              | Puma 대신 Falcon. SSE 연결당 fiber (~KB) 로 처리, 새로고침 폭주에 안전.                |
| DB      | **SQLite (dev) / PostgreSQL-ready**                              | 셋업 friction 0. ActiveRecord 라 마이그레이션은 PG 도 그대로 동작.                     |
| File    | **Active Storage (Disk service)**                                | 음성 blob 영속화. S3/GCS 로 갈아끼우려면 `storage.yml` 한 줄.                          |
| LLM     | **Gemini MODEL_CHAIN (6-model fallback, streaming)**             | 3.1-flash-lite-preview → 3-flash-preview → 2.5-flash → 2.5-flash-lite → 2.0-flash → 2.0-flash-lite. 429/에러 시 자동 폴백. |
| STT     | **Gemini STT_MODEL_CHAIN (4-model fallback)**                    | 2.5-flash → 2.5-flash-lite → 2.0-flash → 2.0-flash-lite. 오디오 입력 지원 모델만.    |
| TTS     | **ElevenLabs + browser SpeechSynthesis fallback**                | ElevenLabs 실패 시 브라우저 내장 TTS 로 자동 전환. 무료 10K chars/월.                  |
| 번역    | **Google Translate (무료 gtx API)**                               | Gemini 토큰 소모 없이 대화 버블 한글 번역. 30일 Rails.cache.                           |
| VAD     | **@ricky0123/vad-web (Silero VAD)**                              | 브라우저에서 동작 → 공백 구간 절약 → STT 호출량 감소.                                  |
| Front   | **React + TypeScript + Vite + Zustand + React Query**             | Vite HMR, 작은 surface 의 Zustand persist 로 X-User-Id / 대화 id 를 localStorage 보관.|
| Test    | **RSpec + factory_bot + WebMock**, **Vitest + RTL**                | "퀄리티 있는 테스트 코드" 요구 충족.                                                   |

### 2-2. 인증 / 권한

과제 명시적 제외 사항이라 **JWT/세션 기반 인증을 의도적으로 구현하지 않았습니다**.
대신 호출자 식별은 `X-User-Id` 헤더 stub 으로 처리하고, 컨트롤러 단에서
`require_user!` / `require_admin!` / `require_talk_feature!` helper 가 권한을
검증합니다. 프로덕션에서는 stub 을 토큰 디코딩으로 갈아끼우면 끝나는 구조입니다.

### 2-3. 멤버십 모델

```
┌─────────────────┐    1     N ┌──────────────┐    N     1 ┌──────────────────┐
│      User       │────────────│  Membership  │────────────│ MembershipPlan   │
│ id, email, role │            │ status,      │            │ features[],      │
│                 │            │ source,      │            │ duration_days,   │
│                 │            │ started/exp  │            │ price_cents      │
└─────────────────┘            └──────────────┘            └──────────────────┘
                                       │
                                       │ 1
                                       │
                                ┌──────────────┐
                                │   Payment    │
                                │ pg_tx_id …   │
                                └──────────────┘
```

- `MembershipPlan.features` 는 `JSON` 컬럼으로 `["study","talk","analysis"]` 의
  부분집합. 새 기능을 추가할 때 마이그레이션 없이 seed 에서 enum 만 늘리면 됩니다.
- `Membership.state` 는 `status` (active|revoked) 와 `expires_at` 를 합쳐 lazy
  계산: 만료 시간이 지나면 column 을 건드리지 않아도 `state == "expired"` 가 됩니다.
- `User#has_feature?` 는 활성 멤버십들의 features union 을 본다 — 같은 유저가
  여러 멤버십을 동시에 들고 있어도 features 가 합쳐집니다.

### 2-4. 결제 (Mock PG)

`PaymentGateway` 는 토큰 기반 mock 입니다. 토큰별로 결과가 분기되도록 설계해서
**테스트와 데모에서 모든 실패 경로를 직접 재현할 수 있습니다**. 토큰 vocabulary 는
Stripe / TossPayments 의 test card 컨벤션을 의도적으로 모방했기 때문에, 추후
실제 PG 로 갈아끼울 때 `Memberships::Purchase` 를 건드릴 필요가 없습니다.

| 토큰                    | 결과                                | HTTP                             |
| ----------------------- | ----------------------------------- | -------------------------------- |
| `tok_visa`              | 성공                                | 201                              |
| `tok_mastercard`        | 성공                                | 201                              |
| `tok_visa_declined`     | DeclinedError(`card_declined`)      | 402 `payment_declined`           |
| `tok_insufficient`      | DeclinedError(`insufficient_funds`) | 402 `payment_declined`           |
| `tok_processing_error`  | ProcessingError                     | 502 `payment_processing_error`   |
| (unknown)               | DeclinedError(`unknown_card`)       | 402                              |

`Memberships::Purchase` 서비스는 `ActiveRecord::Base.transaction` 로 감싸기 때문에
PG 가 raise 하면 멤버십/Payment 행 둘 다 롤백됩니다 (테스트에 명시적 케이스 있음).

### 2-5. 대화 영속화

```
┌──────────┐    1   N ┌──────────────┐    1     N ┌────────────┐
│   User   │──────────│ Conversation │────────────│  Message   │
│          │          │ title,       │            │ role,text, │
│          │          │ study_mat_id │            │ position   │
└──────────┘          └──────┬───────┘            └─────┬──────┘
                             │ 1    N                   │ has_one_attached
                             │                          ▼
                      ┌──────────────┐          ┌──────────────┐
                      │  Analysis    │          │ Active       │
                      │ status,result│          │ Storage Blob │
                      │ analyzed_at  │          └──────────────┘
                      └──────────────┘
                           │              │  (mp3/wav)   │
                           ▼              └──────────────┘
                      모든 메시지 + 첨부 blob 까지 cascade 삭제
```

- 모든 대화는 명시적 삭제 (`DELETE /api/v1/conversations/:id`) 전까지 영구히
  남고, 메시지마다 음성 첨부도 같이 보존됩니다. 새로고침 / 다른 탭에서도 그대로
  재생 가능합니다.
- `Message.position` 은 conversation 내부에서 0부터 단조 증가. SSE 스트림이
  중간에 끊겨도 `Conversation#append_message!` 가 다음 position 을 다시 계산해서
  채워주기 때문에 데이터 무결성이 깨지지 않습니다.
- 음성 blob 은 우리 자체 컨트롤러 (`MessagesController#audio`) 로만 서빙해서
  Active Storage 의 public URL 이 X-User-Id 검사를 우회하지 못하게 합니다.

### 2-6. AI 분석 기능

`analysis` 멤버십 기능을 가진 사용자가 과거 대화를 선택하면 Gemini가 영어 레벨을
분석합니다. 분석 결과는 `analyses` 테이블에 영속 저장되어 재방문 시 즉시 표시됩니다.

- **비동기 처리**: POST 요청 → `Analysis` 레코드 생성(pending) → 백그라운드 Thread에서
  Gemini 호출 → 완료 시 `AnalysisBus.publish` → SSE push로 프론트 알림
- **분석 항목**: 종합 레벨(novice~advanced), 문법(점수+오류교정), 어휘(점수+대체표현),
  유창성, 주제 관련성, 핵심 표현 활용도, 개선 제안
- **쿨다운**: 동일 대화에 대해 30초 간격 제한
- **한국어 피드백**: 분석 프롬프트가 한국어 응답을 지시

### 2-7. TTS 비용 절감 (TtsArtifact)

```
                        text "Hi! I'm Ringle..."
                                  │
                                  ▼
                           SHA256 content_hash
                                  │
                                  ▼
                ┌─────────────────────────────────┐
                │ TtsArtifact.find_by(            │
                │   content_hash, voice, model)   │
                └─────────────────────────────────┘
                          │              │
                       hit│              │miss
                          ▼              ▼
              cached audio.download   ElevenLabsClient#synthesize
                          │              │
                          │              └─→ TtsArtifact.create + attach
                          │                          │
                          └────────┬─────────────────┘
                                   ▼
                              MP3 bytes
```

- `Tts::Synthesize.call(text:)` 가 ElevenLabs 호출의 **유일한 경로** 입니다.
  `SpeechController` 는 항상 이 서비스를 거치므로 같은 텍스트는 같은 음성/모델
  조합으로 한 번만 과금됩니다.
- 응답 헤더에 `X-Tts-Cache: hit|miss` 를 실어 클라이언트/모니터링에서 캐시
  상태를 직접 볼 수 있습니다.

### 2-7. 클라이언트 음성 재생 lookup (3-tier)

```
사용자가 ▶ 클릭
   │
   ▼
1) in-memory cache (Map<turnId, Blob>)        ─ same session, 0 network
   │ miss
   ▼
2) message.audio_url → fetchMessageAudio()    ─ persisted disk, 0 AI bill
```

재생은 캐시 전용 (in-memory 또는 서버 blob). TTS 재합성 폴백은 제거되었습니다 (튜터 목소리로 학습자 발화를
재합성하지 않기 위해서). PDF 명시 요구사항: "유저가 본인이 말한 것 혹은 AI가
말했던 것을 다시 듣고 싶으면 재생 버튼".

### 2-8. 응답 지연 최소화

```
SSE 토큰 도착 ──┐
              │  SentenceSplitter 로 문장 경계 검출
              │            │
              │            ▼
              │     문장 완성 시점에 즉시 fetchTtsBlob(sentence)
              │            │
              │            ▼
              │     AudioQueue.enqueue(promise)  ── 도착 순서 보장하며 순차 재생
              ▼
        화면 텍스트 업데이트
```

- LLM streaming + per-sentence parallel TTS + 도착 순서 큐 ⇒ 첫 음성이 첫 토큰
  도착 후 ~1s 안에 재생됩니다.
- VAD 가 사용자 음성에서 공백을 잘라내므로 STT 페이로드가 평균 30~50% 줄어듭니다.

### 2-9. 오남용 방지

| 위협                                                    | 방어                                                        |
| ------------------------------------------------------- | ----------------------------------------------------------- |
| 마이크를 열어둔 채 무한 요청                            | 클라이언트: `MAX_RECORDING_MS=30s` 하드 캡 + VAD silence cut |
| AI 엔드포인트 요청 폭주                                 | 서버: `rack-attack` per-user 20/min, 200/hour                |
| 다른 도메인에서 우리 API 호출                           | 서버: `rack-cors` 가 `FRONTEND_ORIGIN` 만 화이트리스트       |
| 멤버십 없는 유저가 LLM 번 토큰 소모                      | `require_talk_feature!` before_action                        |
| 같은 텍스트로 ElevenLabs 토큰 반복 소모                  | `TtsArtifact` content_hash 캐시 (서버측)                     |
| 새로고침마다 ElevenLabs 다시 호출                        | 메시지별 음성 영속화 + 재생 lookup 3-tier                    |
| 다른 유저의 음성 blob 직접 접근                          | `MessagesController#audio` 가 ownership 검사 후에만 stream  |
| SSE 새로고침 폭주                                               | rack-attack SSE per-user 30/min, per-IP 60/min + Bus 동시 캡 8   |
| AI 토픽 생성 시 욕설                                            | ContentFilter denylist (EN+KO) + Gemini safetySettings           |
| 욕설 반복 시 생성 쿼터 소모                                      | 3회 누적마다 study_generations_used +1 (페널티)                   |
| AI 토픽 무한 생성                                               | per-user 생성 한도 3회 (study_generations_used)                   |

---

## 3. 테스트 / 검증 방법

### 3-1. Backend (RSpec)

```bash
cd backend
bundle exec rspec
```

총 246 examples, 전부 통과.

| 영역                            | 주요 케이스                                                                      |
| ------------------------------- | -------------------------------------------------------------------------------- |
| `models/membership_spec`        | state 머신 (active/expired/revoked), 만료 시각 검증                              |
| `models/conversation_spec`      | append_message 의 position 자동 증가, audio attach, cascade 삭제                 |
| `services/payment_gateway_spec` | 5종 카드 토큰 분기 + unknown 토큰 declined fallback                              |
| `services/tts_synthesize_spec`  | 첫 호출 ElevenLabs 1회, 두 번째 호출 캐시 hit (호출 0회)                          |
| `requests/payments_spec`        | 정상/거절/processing_error 별 HTTP 코드, 롤백, 401                               |
| `requests/conversations_spec`   | 생성/조회/삭제/owner 검증, talk feature 가드, audio_url 직렬화                   |
| `requests/ai/speech_spec`       | TTS 캐시 헤더 hit/miss, 에러 매핑, talk feature 가드                              |
| `services/content_filter_spec`   | EN word-boundary + KO substring, borderline 단어 통과 검증                            |
| `services/gemini_client_spec`    | safety block 감지, safetySettings 주입, STT fallback 체인 (4-model 순회)               |
| `requests/sse_throttling_spec`   | rack-attack 30/min 발화, Bus MAX_PER_USER=8 cap, 컨트롤러 에러 이벤트                 |
| `requests/me_stream_spec`        | 초기 snapshot, query auth, 멤버십 변경/만료 시 자동 푸시                               |

### 3-2. Frontend (Vitest + Testing Library)

```bash
cd frontend
pnpm test       # = vitest run
pnpm typecheck  # = tsc --noEmit
```

| 파일                         | 검증                                                     |
| ---------------------------- | -------------------------------------------------------- |
| `pages/HomePage.test.tsx`    | 멤버십/플랜 렌더, test_cards 셀렉터, payment_method 송신 |
| `lib/api.test.ts`            | apiFetch 헤더/에러 매핑                                  |
| `lib/audio.test.ts`          | WAV 인코더 16kHz mono                                    |
| `lib/sentences.test.ts`      | SentenceSplitter 경계 검출                               |
| `pages/StudyPage.test.tsx`   | 커리큘럼 렌더, talk 유무에 따른 CTA 분기                      |
| `components/TopBar.test.tsx` | 탭 동적 렌더, feature 별 노출                                |

### 3-3. 수동 검증 체크리스트

- [ ] 홈에서 `tok_visa_declined` 골라 결제 → 402 + UI 에 "거절" 메시지 표시
- [ ] 정상 결제 후 멤버십 행이 나타남
- [ ] /conversation 진입 → 인사말 자동 재생 (오디오 들려야 함)
- [ ] 마이크 → 답변 완료 → 응답 텍스트 + 음성 도착
- [ ] 응답 종료 후 새로고침 → 모든 메시지 + ▶ 버튼 그대로
- [ ] 새로고침 후 ▶ 클릭 → 음성이 다시 들림 (서버 disk hit, X-Tts-Cache 헤더)
- [ ] 사용자 본인 발화 ▶ → WAV 가 그대로 재생
- [ ] Dev 패널 → "현재 대화 삭제" → /conversation 다시 들어가면 새 대화로 시작
- [ ] Admin 계정으로 전환 → /admin → 다른 유저에게 멤버십 부여/회수

---

## 4. 디렉토리 구조

```
backend/
├─ app/
│  ├─ controllers/api/v1/
│  │  ├─ me_controller.rb
│  │  ├─ me_stream_controller.rb          # SSE /me/stream
│  │  ├─ membership_plans_controller.rb
│  │  ├─ memberships_controller.rb
│  │  ├─ payments_controller.rb
│  │  ├─ conversations_controller.rb
│  │  ├─ messages_controller.rb
│  │  ├─ study_materials_controller.rb
│  │  ├─ study_materials_stream_controller.rb  # SSE /study_materials/stream
│  │  ├─ stt_fixtures_controller.rb
│  │  ├─ admin/
│  │  │  ├─ users_controller.rb
│  │  │  ├─ memberships_controller.rb
│  │  │  ├─ membership_stream_controller.rb    # SSE /admin/memberships/stream
│  │  │  └─ study_materials_controller.rb      # reset, delete AI, counters
│  │  └─ ai/
│  │     ├─ messages_controller.rb             # SSE streaming LLM
│  │     ├─ analysis_controller.rb            # 분석 요청/조회
│  ├─ analysis_stream_controller.rb           # SSE /analysis/stream
│  │     ├─ transcriptions_controller.rb
│  │     ├─ speech_controller.rb
│  │     └─ translations_controller.rb         # Google Translate
│  ├─ models/   User, Membership, MembershipPlan, Payment,
│  │            Conversation, Message, Analysis, TtsArtifact, SttArtifact, StudyMaterial
│  └─ services/
│     ├─ gemini_client.rb          # LLM streaming + STT (4-model fallback)
│     ├─ eleven_labs_client.rb
│     ├─ google_translate_client.rb
│     ├─ payment_gateway.rb
│     ├─ content_filter.rb         # 욕설 denylist (EN+KO)
│     ├─ memberships/              # purchase (stacking), admin_grant
│     ├─ tts/synthesize.rb
│     ├─ stt/                      # transcribe, fixture_library, fixture_seed
│     ├─ study_materials/          # generate, curriculum_seed, reset
│     ├─ conversations/summarize.rb  # 컨텍스트 메모리 요약
│     ├─ conversations/analyze.rb   # AI 영어 레벨 분석
│     ├─ analysis_bus.rb            # SSE 분석 상태 push
│     ├─ me/                       # bus, snapshot
│     ├─ admin/membership_bus.rb
│     └─ study/bus.rb
├─ config/initializers/
│  ├─ cors.rb
│  └─ rack_attack.rb              # AI + SSE rate limit
├─ db/migrate/                     # 18 migrations
└─ spec/                           # rspec, 246 examples

frontend/
├─ src/
│  ├─ pages/        HomePage, HistoryPage, StudyPage, ConversationPage,
│  │                AnalysisPage, AdminPage (+tests)
│  ├─ components/   TopBar, DevPanel, RequireAccess, PaymentModal,
│  │                LoadingScreen, MembershipRow, MeStreamSubscriber,
│  │                StudyMaterialsSubscriber, AdminMembershipsSubscriber (+tests)
│  ├─ lib/
│  │  ├─ api.ts                    # apiFetch + streamAiMessages + translateText
│  │  ├─ conversations.ts
│  │  ├─ ttsCache.ts               # fetchTtsBlob + fetchTtsWithFallback
│  │  ├─ speech.ts                 # browser SpeechSynthesis fallback
│  │  ├─ speakable.ts              # ___ → "blank" 변환
│  │  ├─ useVoiceRecorder.ts       # MicVAD + waveform
│  │  ├─ audioQueue.ts
│  │  ├─ sentences.ts
│  │  ├─ useMeStream.ts            # SSE /me/stream subscriber
│  │  ├─ useAnalysisStream.ts     # SSE /analysis/stream subscriber
│  │  ├─ serverTime.ts            # 서버 시간 offset + 타임존 포매팅
│  │  ├─ useAdminMembershipsStream.ts
│  │  ├─ useStudyMaterialsStream.ts
│  │  ├─ validation.ts             # zod schema (admin grant duration)
│  │  ├─ format.ts
│  │  ├─ queries.ts                # react-query hooks
│  │  ├─ types.ts
│  │  └─ userStore.ts              # zustand persist
│  └─ global.css
└─ vitest 18 tests
```

---

## 5. 실시간 상태 동기화 (SSE) — 폴링을 대체한 이유와 production 경로

### 왜 폴링이 아닌 SSE인가

ConversationPage 가 30초짜리 테스트 멤버십을 사용 중일 때, 만료된 순간 즉시
사용자를 바운스해야 한다는 요구사항이 있습니다. 초기 구현은 `/me` 를 4초마다
폴링하는 방식이었지만 두 가지 문제가 있어서 SSE 푸시로 갈아탔습니다:

- **반응성** — 폴링 4초 → 만료 감지가 최악 4초 지연. SSE 는 만료 deadline 에서
  서버가 정확히 그 순간 푸시해서 100ms 미만.
- **부하** — 페이지에 머무는 동안 계속 GET 호출 발생. 멀티 페이지/탭 환경에서
  `/me` 가 끊임없이 들어오는 게 로그 가독성도 해치고 의미 없는 DB hit.

### 채널 네 개

```
┌──────────────────────┬─────────────────────┬─────────────────────────────────┐
│ 채널                 │ 키                  │ 트리거                          │
├──────────────────────┼─────────────────────┼─────────────────────────────────┤
│ Me::Bus              │ user_id             │ 본인 멤버십 변화 / 만료         │
│ Admin::MembershipBus │ (글로벌)            │ 누구든 멤버십 변화/만료         │
│ Study::Bus           │ (글로벌)            │ 커리큘럼 생성/리셋              │
│ AnalysisBus          │ user_id             │ 분석 완료/실패                  │
└──────────────────────┴─────────────────────┴─────────────────────────────────┘
```

`Membership` 모델의 `after_commit` 콜백이 두 버스 모두에 publish 합니다.
시간 기반 만료는 row mutation 이 없어서 콜백을 안 타기 때문에, 각 SSE
컨트롤러가 `Queue#pop(timeout: 다음_만료까지)` 로 만료 deadline 에 정확히
깨어나서 같은 코드 경로로 들어갑니다 — *폴링 없이* 만료를 감지합니다.

프론트엔드 쪽:

```
<MeStreamSubscriber />     ← App 루트에 1회 마운트, 로그인된 모든 사용자 자동
  └─ useMeStream()            EventSource → 'snapshot' → setQueryData(['me', id])
                              → useMe() 캐시가 갱신되어 모든 페이지 자동 리렌더

<AdminMembershipsSubscriber /> ← AdminPage 안에서만 마운트
  └─ useAdminMembershipsStream()  EventSource → 'changed' →
                                  invalidateQueries(adminUsers)
                                  → admin/users REST 를 refetch
```

### Falcon (fiber 기반 웹서버) 로 전환한 이유

원래는 Puma + 스레드 모델이었습니다. 그런데 SSE 1 연결이 1 스레드를 점유
한다는 게 문제입니다. Puma 기본 3 스레드 환경에서 사용자가 4번만 새로고침해도
zombie 스레드가 워커 풀을 채워서 일반 REST 요청까지 hang 됩니다.

근본 원인: `Queue#pop(timeout:)` 안에서 자고 있는 스레드는 클라이언트가
TCP FIN 을 보내도 그걸 인지하지 못합니다 (큐를 보고 있지 소켓을 보고 있지
않음). 다음 `sse.write` 시도 시점에 비로소 EPIPE 가 터지고 그제야 청소됩니다.

해결책으로 Puma → Falcon 으로 전환했습니다:

| 항목                  | Puma (이전)        | Falcon (지금)              |
| --------------------- | ------------------ | -------------------------- |
| 동시성 단위           | OS 스레드 (~1MB)   | Fiber (~수 KB)             |
| Close 감지            | 다음 write 시도 시 | 이벤트 루프 즉시 (μs 수준) |
| SSE 연결 1000개       | ~1GB → OOM         | ~몇 MB                     |
| Heartbeat 간격        | 2s (panic mode)    | 30s (정상)                 |
| GVL 영향              | 큼                 | I/O 대기 동안은 yield      |

설정 파일:

- `backend/Gemfile` → `gem 'falcon'`, `gem 'async-http'`
- `backend/config/environments/{development,production}.rb` →
  `config.active_support.isolation_level = :fiber`,
  `config.active_record.async_query_executor = :global_thread_pool`
- `backend/config/database.yml` → SQLite WAL 모드 활성화 + `pool: 32`
  (fiber 가 동시에 DB 쿼리를 띄울 때 connection checkout 막힘 방지)

`bin/rails s -p 3000` 만 돌리면 자동으로 Falcon 이 부팅됩니다 — Gemfile 에서
puma 가 빠지면서 Rails 가 falcon 을 픽합니다.

### 새로고침 폭주에 대한 다층 방어

Falcon 으로 갈아탔다고 무한정 fiber 를 받아주면 안 됩니다. 5분 MAX_DURATION
안에 수천 fiber 가 누적되면 결국 메모리 / FD / Bus 큐 슬롯 한계에 부딪힙니다.
두 층으로 막습니다:

1. **`config/initializers/rack_attack.rb`** — SSE 엔드포인트 신규 오픈을
   per-user 분당 30회, per-IP 분당 60회로 제한. 그 이상은 즉시 429.
2. **`Me::Bus::MAX_PER_USER = 8`** — 동시 구독 절대 캡. subscribe 시 이미 8개
   면 `TooManySubscribersError` raise → 컨트롤러가 catch 해서 `event: error
   too_many_connections` 푸시 후 종료.

검증: `spec/requests/sse_throttling_spec.rb` (4 examples).

### Production 으로 가는 단계별 경로

이 과제는 데모/리뷰 환경 기준이라 SQLite + 단일 Falcon 프로세스로 충분하지만,
실 production 으로 가는 길은 명확합니다:

```
┌────────────────┬─────────────────────────────────────────────────────┐
│ Phase          │ 무엇을 바꾸는가                                     │
├────────────────┼─────────────────────────────────────────────────────┤
│ 0 (현재)       │ Falcon + sqlite + in-process Bus                    │
│                │ - 동시 SSE 수백~수천까지 무난                       │
│                │ - 단일 unit 배포, 디버깅 단순                       │
├────────────────┼─────────────────────────────────────────────────────┤
│ 1 (production) │ DB adapter sqlite → pg                              │
│                │ - database.yml adapter / host / pool 변경           │
│                │ - 스키마는 그대로 (호환)                            │
│                │ - async_query_executor: :global_thread_pool 로      │
│                │   pg sync 호출도 fiber yield                        │
├────────────────┼─────────────────────────────────────────────────────┤
│ 2 (multi-node) │ 멀티 프로세스/멀티 머신                             │
│                │ - in-process Bus → Redis Pub/Sub 으로 교체          │
│                │ - Me::Bus / Admin::MembershipBus 의 publish/        │
│                │   subscribe 인터페이스만 그대로 유지하면 됨         │
│                │ - 모듈 안에서 Concurrent::Map → Redis CHANNEL       │
├────────────────┼─────────────────────────────────────────────────────┤
│ 3 (10k+ SSE)   │ SSE Gateway 를 별도 프로세스로 분리                 │
│                │   Nginx                                             │
│                │     ↓ (connection cap, rate limit, TLS)             │
│                │   SSE Gateway (Node/Go)                             │
│                │     ↓                                               │
│                │   Redis Pub/Sub                                     │
│                │     ↓                                               │
│                │   Rails API (비즈니스 로직만)                       │
│                │ - 비즈니스 로직과 SSE 부하의 격리                   │
│                │ - 각 레이어 독립 스케일                             │
│                │ - 인프라 복잡도는 4배                               │
└────────────────┴─────────────────────────────────────────────────────┘
```

Phase 0 → 1 은 데이터베이스 한 줄 + adapter 가 끝이고, 1 → 2 는 Bus 모듈 한
파일을 Redis 어댑터로 교체하면 됩니다. 3 단계는 동시 SSE 가 단일 머신
한계(보통 10k+) 에 부딪힐 때만 의미 있습니다.

---

## 6. 알려진 한계 / 가정

- **실제 PG 연동 없음** — 과제 제외 사항. `PaymentGateway` 는 명시적 mock.
- **인증 없음** — 과제 제외 사항. `X-User-Id` 헤더 stub.
- **대화 세션은 사용자당 1개** — 다중 세션 UX 는 구현 안 함 (PDF 가 optional).
  서버는 N 개의 conversation 을 저장할 수 있고, `userStore` 의
  `conversationByUser` 는 사용자별 "현재 대화 id" 만 들고 있습니다.
- **Gemini 2.5 Flash STT** — 한국어 발화도 인식하지만 출력은 영어로 옮겨주는
  편향이 있어 영어 학습 시나리오에 부합합니다.
- **ElevenLabs 무료 voice** — 계정에 따라 사용 가능한 voice 가 다르므로
  `ElevenLabsClient#voice_id` 가 `/v1/voices` 를 한 번 조회해 자동 선택합니다.
- **동일 플랜 멤버십 stacking** — 같은 plan 의 active 멤버십이 있으면 `expires_at` 에 기간을 합산합니다.
- **학습 커리큘럼 생성 한도** — per-user 3회, 욕설 3회 누적 시 1회 차감 페널티.
- **번역** — Google Translate 무료 gtx API 사용. Gemini 토큰 불소모. 30일 Rails.cache.
- **컨텍스트 메모리** — 6턴 이상이면 오래된 턴을 Gemini 로 2~3문장 요약 후 `conversations.context_summary` 에 저장. system instruction 에 주입.
- **TTS 폴백** — ElevenLabs 실패 시 브라우저 SpeechSynthesis 로 자동 전환.
