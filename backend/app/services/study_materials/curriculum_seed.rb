module StudyMaterials
  # Hand-curated starter curriculum so the /study tab works the moment
  # you boot the app, without any Gemini key. Each entry is a tightly
  # scoped scenario the AI tutor would suggest as a first conversation,
  # with a few key expressions and an example exchange so the learner
  # has something to latch onto.
  #
  # Bilingual dialogue convention: the assistant lines are written in
  # Korean (the learner's L1) but ALWAYS embed the target English key
  # expressions verbatim. The point is to give the learner a worked
  # example of "when do I switch to English?" — the tutor explains
  # context in Korean and models the English expression at the right
  # moment. The user lines stay in English because that's what the
  # learner is practicing producing.
  #
  # `StudyMaterials::Generate` (which calls Gemini) appends to the
  # same table — both seeded and AI-generated rows look identical to
  # the frontend except for the `ai_generated` flag.
  class CurriculumSeed
    SEED = [
      # ─── 일상 / 비즈니스 / 여행 / 학술 / 취미 — 기존 시나리오를 한글-영어 혼합으로 갱신 ───
      {
        slug: "introduce-yourself",
        title: "Introducing Yourself at Work",
        level: "beginner",
        category: "business",
        description: "처음 만난 동료에게 본인을 소개해보세요. 이름, 직책, 회사를 자연스럽게 말하는 패턴을 익힙니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, an English tutor. The learner is practicing introducing themselves
          in a business setting to a new colleague. Stay on-topic: ask about their name,
          role, company, and what they do day-to-day. Gently rephrase any grammar mistakes
          and end every reply with one short follow-up question. Keep replies under
          two sentences.
        PROMPT
        key_expressions: [
          "Hi, I'm ___ . I work as a ___ at ___ .",
          "Nice to meet you. What about you?",
          "I've been in this role for about ___ ."
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "안녕하세요! 오늘은 자기소개를 연습해볼게요. 처음 만난 동료에게 이렇게 시작해 보세요: \"Hi, I'm ___ . I work as a ___ at ___ .\"" },
          { "role" => "user",      "text" => "Hi, I'm Danny. I work as a backend engineer at Ringle." },
          { "role" => "assistant", "text" => "좋아요! 자연스러웠어요. 이번엔 상대방에게 같은 질문을 돌려주는 표현을 써볼까요? \"Nice to meet you. What about you?\"" }
        ]
      },
      {
        slug: "ordering-coffee",
        title: "Ordering Coffee on the Go",
        level: "novice",
        category: "daily",
        description: "카페에서 음료를 주문하고 사이즈, 옵션을 추가하는 짧은 대화를 연습합니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, an English tutor playing the role of a cafe barista. Walk the
          learner through ordering a drink: greet them, ask for their order, confirm
          size, and ask about extras (milk, syrup, ice). Switch back to tutor mode if
          they make a mistake — gently rephrase, then continue the role-play. Keep
          replies under two sentences.
        PROMPT
        key_expressions: [
          "Can I get a ___ , please?",
          "I'll have a tall / grande / venti ___ .",
          "Could you make it iced / hot?"
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "카페에서 주문할 때는 이렇게 말하면 자연스러워요: \"Can I get a ___ , please?\" 한 번 따라 해 볼게요. 무엇을 주문하고 싶으세요?" },
          { "role" => "user",      "text" => "Can I get a grande iced latte, please?" },
          { "role" => "assistant", "text" => "완벽해요. 사이즈와 옵션까지 잘 말했네요. 차가운 음료가 좋다면 \"Could you make it iced?\" 라고도 자주 써요." }
        ]
      },
      {
        slug: "weekend-plans",
        title: "Weekend Plans Small Talk",
        level: "intermediate",
        category: "daily",
        description: "동료와 가벼운 주말 계획을 주고받으며 자연스러운 small talk 표현을 늘립니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, an English tutor making small talk about weekend plans. Ask
          the learner what they're doing this weekend, share a short fictional plan of
          your own, and follow up with a related question. Keep the tone casual,
          replies under two sentences, and gently fix any awkward phrasing.
        PROMPT
        key_expressions: [
          "Any plans for the weekend?",
          "I'm thinking of ___ .",
          "How about you?"
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "주말 small talk을 연습해볼게요. 가볍게 운을 떼는 표현이에요: \"Any plans for the weekend?\"" },
          { "role" => "user",      "text" => "I'm thinking of going hiking on Saturday." },
          { "role" => "assistant", "text" => "좋네요! 상대방에게 다시 질문할 때는 \"How about you?\" 로 자연스럽게 마무리할 수 있어요." }
        ]
      },
      {
        slug: "stand-up-update",
        title: "Daily Stand-up Update",
        level: "intermediate",
        category: "business",
        description: "데일리 스탠드업에서 어제 한 일, 오늘 할 일, 막힌 부분을 영어로 보고합니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, an English tutor running a mock stand-up. Ask the learner for
          three things in order: what they did yesterday, what they're doing today, and
          any blockers. Encourage concise replies, rephrase grammar mistakes, and
          finish with a one-line summary of what they said.
        PROMPT
        key_expressions: [
          "Yesterday I ___ .",
          "Today I'm planning to ___ .",
          "I'm blocked on ___ ."
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "스탠드업 미팅을 시작해볼게요. 어제 한 일을 이렇게 말하면 돼요: \"Yesterday I ___ .\"" },
          { "role" => "user",      "text" => "Yesterday I finished the auth refactor." },
          { "role" => "assistant", "text" => "잘했어요. 오늘 계획은 \"Today I'm planning to ___ .\" 로 이어가면 자연스러워요." }
        ]
      },

      # ─── 회화(conversation) — 5개 더미 시나리오 ───
      {
        slug: "convo-self-intro-casual",
        title: "친구에게 자기 소개하기",
        level: "novice",
        category: "conversation",
        description: "처음 만난 또래 친구에게 가볍게 자기 소개를 해보는 회화 시나리오입니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, a friendly English-speaking peer the learner just met at a
          casual meetup. Keep the register relaxed, ask for their name, where they're
          from, and what they like to do. Reply in 1-2 sentences, fix slips gently,
          and end with one follow-up question.
        PROMPT
        key_expressions: [
          "Hey, I'm ___ . What's your name?",
          "Where are you from?",
          "What do you like to do for fun?"
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "친구에게 가볍게 인사하는 회화예요. 이렇게 시작해 봅시다: \"Hey, I'm ___ . What's your name?\"" },
          { "role" => "user",      "text" => "Hey, I'm Danny. What's your name?" },
          { "role" => "assistant", "text" => "좋아요! 이어서 출신지를 묻고 싶다면 \"Where are you from?\" 이라고 해보세요." }
        ]
      },
      {
        slug: "convo-asking-directions",
        title: "길 물어보기",
        level: "beginner",
        category: "conversation",
        description: "낯선 도시에서 행인에게 가까운 지하철역까지 가는 길을 물어보는 회화입니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, a polite passerby in an English-speaking city. The learner
          is asking for directions to the nearest subway. Give clear short directions,
          use one landmark, and end by checking they understand. Keep it 1-2 sentences.
        PROMPT
        key_expressions: [
          "Excuse me, could you tell me how to get to ___ ?",
          "Is it within walking distance?",
          "Thank you so much!"
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "처음 보는 사람에게 길을 물을 땐 정중하게 시작해요: \"Excuse me, could you tell me how to get to ___ ?\"" },
          { "role" => "user",      "text" => "Excuse me, could you tell me how to get to the nearest subway?" },
          { "role" => "assistant", "text" => "두 블록만 직진하면 보여요. 거리가 궁금하다면 \"Is it within walking distance?\" 라고 한 번 더 물어볼 수 있어요." }
        ]
      },
      {
        slug: "convo-restaurant-recommendation",
        title: "맛집 추천 받기",
        level: "intermediate",
        category: "conversation",
        description: "현지인에게 근처 괜찮은 식당을 추천받고 음식 종류, 가격대를 묻는 회화입니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, a local who knows the neighborhood well. The learner asks
          for a restaurant recommendation. Suggest one place, mention the cuisine and
          rough price range, and ask if they have any dietary restrictions. Keep it
          short and warm.
        PROMPT
        key_expressions: [
          "Do you know any good places to eat around here?",
          "What kind of food do they serve?",
          "Is it pretty pricey?"
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "근처 맛집을 물어볼 땐 이렇게 시작해 봅시다: \"Do you know any good places to eat around here?\"" },
          { "role" => "user",      "text" => "Do you know any good places to eat around here?" },
          { "role" => "assistant", "text" => "두 블록 옆에 작은 이탈리안 식당이 있어요. 가격이 궁금하면 \"Is it pretty pricey?\" 라고 한 번 물어보세요." }
        ]
      },
      {
        slug: "convo-meeting-disagreement",
        title: "회의에서 정중하게 반대하기",
        level: "advanced",
        category: "conversation",
        description: "회의 중 동료의 의견에 정중하게 반대하고 본인의 입장을 설명하는 회화입니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, a coworker in a meeting where the learner needs to politely
          push back on a proposal. Validate their concern, model one diplomatic
          counter-argument, and prompt them to expand on their reasoning. Keep replies
          under two sentences.
        PROMPT
        key_expressions: [
          "I see your point, but I'm not sure that ___ .",
          "Could we consider ___ instead?",
          "I'd like to push back on this for a moment."
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "회의에서 정중하게 반대 의견을 낼 때는 부드러운 시작이 중요해요: \"I see your point, but I'm not sure that ___ .\"" },
          { "role" => "user",      "text" => "I see your point, but I'm not sure that shipping this week is realistic." },
          { "role" => "assistant", "text" => "잘 시작했어요. 대안을 제안할 땐 \"Could we consider ___ instead?\" 같은 표현이 자연스러워요." }
        ]
      },
      {
        slug: "convo-job-interview-strengths",
        title: "면접에서 강점 어필하기",
        level: "advanced",
        category: "conversation",
        description: "면접관에게 본인의 강점과 그 근거를 짧고 명확하게 설명하는 회화입니다.",
        scenario_prompt: <<~PROMPT.strip,
          You are Ringle, an English-speaking interviewer. Ask the learner about their
          biggest strength and prompt them to back it up with one concrete example.
          Provide gentle feedback on phrasing, and ask one short follow-up.
        PROMPT
        key_expressions: [
          "One of my biggest strengths is ___ .",
          "For example, in my last role I ___ .",
          "That's something I'd love to bring to this team."
        ],
        example_dialogue: [
          { "role" => "assistant", "text" => "면접에서 강점을 말할 땐 두 단계로 가요. 먼저 강점, 다음 예시. 시작은 이렇게요: \"One of my biggest strengths is ___ .\"" },
          { "role" => "user",      "text" => "One of my biggest strengths is staying focused under pressure." },
          { "role" => "assistant", "text" => "좋은 강점이에요. 이어서 구체적인 사례를 \"For example, in my last role I ___ .\" 로 연결해 보세요." }
        ]
      },

      # ─── 입문 (novice) — 추가 시나리오 ───
      {
        slug: "novice-greetings",
        title: "기본 인사 주고받기",
        level: "novice",
        category: "daily",
        description: "처음 보는 사람과 가장 기본적인 인사를 주고받는 연습입니다.",
        scenario_prompt: "You are Ringle, an English tutor. Practice basic greetings: hello, how are you, nice to meet you. Keep it short and warm.",
        key_expressions: ["Hello, how are you?", "I'm good, thanks. And you?", "Nice to meet you."],
        example_dialogue: [
          { "role" => "assistant", "text" => "가장 기본적인 인사부터 시작해요: \"Hello, how are you?\"" },
          { "role" => "user",      "text" => "Hello, how are you?" },
          { "role" => "assistant", "text" => "잘했어요. 답할 땐 \"I'm good, thanks. And you?\" 로 자연스럽게 받아요." }
        ]
      },
      {
        slug: "novice-numbers-time",
        title: "숫자와 시간 말하기",
        level: "novice",
        category: "daily",
        description: "약속 시간을 정할 때 숫자와 시간을 영어로 말해봅니다.",
        scenario_prompt: "You are Ringle, an English tutor. Help the learner say numbers and times of day. Keep replies under two sentences.",
        key_expressions: ["It's ___ o'clock.", "Let's meet at ___ .", "How about ___ ?"],
        example_dialogue: [
          { "role" => "assistant", "text" => "약속 시간을 정해볼게요. 현재 시간은 이렇게 말해요: \"It's three o'clock.\"" },
          { "role" => "user",      "text" => "Let's meet at five." },
          { "role" => "assistant", "text" => "좋아요! 상대방에게 시간을 제안할 땐 \"How about ___ ?\" 도 자주 써요." }
        ]
      },
      {
        slug: "novice-shopping-basic",
        title: "가격 묻고 답하기",
        level: "novice",
        category: "travel",
        description: "여행지 상점에서 물건의 가격을 묻고 답하는 짧은 회화입니다.",
        scenario_prompt: "You are Ringle, role-playing a friendly shopkeeper. Help the learner ask the price of an item and confirm the amount. Keep replies under two sentences.",
        key_expressions: ["How much is this?", "It's ___ dollars.", "I'll take it."],
        example_dialogue: [
          { "role" => "assistant", "text" => "가게에서 가격을 물을 땐 이렇게 시작해요: \"How much is this?\"" },
          { "role" => "user",      "text" => "How much is this?" },
          { "role" => "assistant", "text" => "12달러예요. 사겠다고 답하려면 \"I'll take it.\" 이라고 짧게 말하면 돼요." }
        ]
      },

      # ─── 초급 (beginner) — 추가 시나리오 ───
      {
        slug: "beginner-airport-checkin",
        title: "공항 체크인 카운터",
        level: "beginner",
        category: "travel",
        description: "공항 체크인 카운터에서 짐을 부치고 좌석을 확인하는 짧은 대화입니다.",
        scenario_prompt: "You are Ringle, an airline check-in agent. Help the learner check a bag and confirm a seat. Stay friendly, short replies.",
        key_expressions: ["I'd like to check this bag.", "Could I get a window seat, please?", "Here's your boarding pass."],
        example_dialogue: [
          { "role" => "assistant", "text" => "체크인 카운터에서 짐을 부칠 때 이렇게 말해요: \"I'd like to check this bag.\"" },
          { "role" => "user",      "text" => "I'd like to check this bag." },
          { "role" => "assistant", "text" => "좋아요. 창가 자리가 좋다면 \"Could I get a window seat, please?\" 라고 한 번 더 부탁해 보세요." }
        ]
      },
      {
        slug: "beginner-hobby-talk",
        title: "취미 이야기 나누기",
        level: "beginner",
        category: "hobby",
        description: "동료와 취미를 묻고 답하며 가벼운 라포를 형성합니다.",
        scenario_prompt: "You are Ringle, an English tutor. Casually ask the learner about a hobby and follow up with one related question.",
        key_expressions: ["What do you do in your free time?", "I really enjoy ___ .", "How long have you been doing it?"],
        example_dialogue: [
          { "role" => "assistant", "text" => "취미를 물어볼 땐 이렇게 시작해 봅시다: \"What do you do in your free time?\"" },
          { "role" => "user",      "text" => "I really enjoy hiking." },
          { "role" => "assistant", "text" => "멋져요! 얼마나 오래 했는지 묻고 싶다면 \"How long have you been doing it?\" 라고 이어가요." }
        ]
      },
      {
        slug: "beginner-restaurant-order",
        title: "식당에서 음식 주문하기",
        level: "beginner",
        category: "daily",
        description: "식당에서 메뉴를 보고 음식을 주문하는 기본 회화입니다.",
        scenario_prompt: "You are Ringle, role-playing a server at a restaurant. Help the learner order an entree and a drink. Keep replies short and natural.",
        key_expressions: ["I'd like the ___ , please.", "Could I see the menu?", "I'll have water to drink."],
        example_dialogue: [
          { "role" => "assistant", "text" => "식당에서 주문할 땐 이렇게 시작해요: \"I'd like the ___ , please.\"" },
          { "role" => "user",      "text" => "I'd like the chicken pasta, please." },
          { "role" => "assistant", "text" => "좋아요. 음료는 \"I'll have water to drink.\" 처럼 간단히 덧붙이면 돼요." }
        ]
      },

      # ─── 중급 (intermediate) — 추가 시나리오 ───
      {
        slug: "intermediate-feedback-1on1",
        title: "1:1 미팅에서 피드백 주기",
        level: "intermediate",
        category: "business",
        description: "동료에게 건설적인 피드백을 부드럽게 전달하는 1:1 회화입니다.",
        scenario_prompt: "You are Ringle, coaching the learner on giving constructive 1:1 feedback. Model one piece of feedback, then ask them to phrase one back. Keep replies under two sentences.",
        key_expressions: ["I really appreciate the way you ___ .", "One thing I'd like to suggest is ___ .", "What do you think?"],
        example_dialogue: [
          { "role" => "assistant", "text" => "피드백은 칭찬으로 시작하는 게 자연스러워요: \"I really appreciate the way you ___ .\"" },
          { "role" => "user",      "text" => "I really appreciate the way you handled the customer call." },
          { "role" => "assistant", "text" => "좋아요. 이어서 개선 제안은 \"One thing I'd like to suggest is ___ .\" 로 부드럽게 풀어보세요." }
        ]
      },
      {
        slug: "intermediate-travel-itinerary",
        title: "여행 일정 의논하기",
        level: "intermediate",
        category: "travel",
        description: "친구와 여행 일정을 의논하며 일정 조정과 의견을 주고받는 회화입니다.",
        scenario_prompt: "You are Ringle, a travel buddy planning a 3-day trip with the learner. Suggest an activity, ask for their input, and adjust based on their reply.",
        key_expressions: ["What if we ___ on day one?", "I'm flexible — what works for you?", "Let's lock that in."],
        example_dialogue: [
          { "role" => "assistant", "text" => "여행 일정을 제안할 땐 이렇게 부드럽게 시작해요: \"What if we ___ on day one?\"" },
          { "role" => "user",      "text" => "What if we visit the museum on day one?" },
          { "role" => "assistant", "text" => "좋네요! 결정을 마무리할 땐 \"Let's lock that in.\" 같은 표현이 자연스러워요." }
        ]
      },

      # ─── 고급 (advanced) — 추가 시나리오 ───
      {
        slug: "advanced-negotiate-salary",
        title: "연봉 협상하기",
        level: "advanced",
        category: "business",
        description: "오퍼 단계에서 연봉을 정중하지만 단호하게 협상하는 회화입니다.",
        scenario_prompt: "You are Ringle, role-playing a hiring manager. Help the learner counter a salary offer politely but firmly. Provide a one-line tip after each turn.",
        key_expressions: ["Thank you for the offer — I'd like to discuss the compensation.", "Based on my experience, I was hoping for ___ .", "Is there any flexibility on that?"],
        example_dialogue: [
          { "role" => "assistant", "text" => "연봉 협상은 감사 표현부터 시작해요: \"Thank you for the offer — I'd like to discuss the compensation.\"" },
          { "role" => "user",      "text" => "Thank you for the offer — I'd like to discuss the compensation." },
          { "role" => "assistant", "text" => "좋아요. 본인 기대치를 말할 땐 \"Based on my experience, I was hoping for ___ .\" 처럼 근거를 함께 제시하세요." }
        ]
      },
      {
        slug: "advanced-academic-presentation",
        title: "학술 발표 Q&A 응답",
        level: "advanced",
        category: "academic",
        description: "학술 발표 후 청중의 질문에 침착하게 답하는 회화입니다.",
        scenario_prompt: "You are Ringle, role-playing an audience member at an academic talk. Ask one challenging question and give the learner space to clarify.",
        key_expressions: ["That's a great question.", "To clarify what I meant by ___ , ___ .", "I'd be happy to follow up offline."],
        example_dialogue: [
          { "role" => "assistant", "text" => "Q&A에서 시간을 벌고 싶을 땐 이렇게 시작해요: \"That's a great question.\"" },
          { "role" => "user",      "text" => "That's a great question." },
          { "role" => "assistant", "text" => "좋아요. 답을 명확히 할 땐 \"To clarify what I meant by ___ , ___ .\" 패턴이 유용해요." }
        ]
      },
      {
        slug: "advanced-debate-position",
        title: "토론에서 입장 옹호하기",
        level: "advanced",
        category: "academic",
        description: "토론에서 본인의 입장을 근거와 함께 옹호하는 회화입니다.",
        scenario_prompt: "You are Ringle, debating the learner. Take the opposing position briefly, give them room to defend theirs with evidence, and prompt one rebuttal.",
        key_expressions: ["I'd argue that ___ because ___ .", "The evidence suggests ___ .", "I respectfully disagree."],
        example_dialogue: [
          { "role" => "assistant", "text" => "토론에서 본인 입장을 펼칠 땐 근거와 함께 시작해요: \"I'd argue that ___ because ___ .\"" },
          { "role" => "user",      "text" => "I'd argue that remote work increases productivity because employees control their environment." },
          { "role" => "assistant", "text" => "좋은 시작이에요. 통계나 사례를 덧붙일 땐 \"The evidence suggests ___ .\" 가 자연스러워요." }
        ]
      }
    ].freeze

    def self.call
      SEED.each do |attrs|
        material = StudyMaterial.find_or_initialize_by(slug: attrs[:slug])
        material.assign_attributes(attrs.merge(ai_generated: false))
        material.save!
      end
      StudyMaterial.where(ai_generated: false).count
    end
  end
end
