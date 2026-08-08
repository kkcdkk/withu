# Withy — Google Play 배포 자료

iOS 앱("Withy: make your own character")의 Android 파리티 포트. 이 문서는 Play Console 등록에 필요한 모든 것을 모아둔 단일 소스입니다.

> 상태 요약: **앱 + 위젯 + Wear OS 타일까지 코드 완성·빌드 통과.** 아래 "직접 하셔야 할 것"만 남았습니다.

---

## 1. 스토어 등록 문구 (한국어 — 주 시장)

### 앱 이름 (최대 30자)
```
Withy: 나만의 캐릭터 친구
```

### 짧은 설명 (최대 80자)
```
AI로 만든 나만의 캐릭터가 걸음·수면·날씨에 맞춰 하루 종일 살아 움직여요.
```

### 자세한 설명 (최대 4000자)
```
나만의 캐릭터를 만들고, 하루를 함께 보내세요.

Withy는 내가 직접 만든 캐릭터가 홈 화면과 워치 위에서 살아 움직이는 컴패니언 앱이에요. 내 걸음 수, 운동, 수면, 날씨에 따라 캐릭터의 모습이 하루 종일 바뀝니다. 아침엔 잠에서 깨고, 산책하면 함께 걷고, 밤이 되면 쿨쿨 잠들어요.

■ 나만의 캐릭터 만들기
- AI에게 설명만 적으면 나만의 캐릭터를 그려줘요 (예: "주근깨 많은 분홍 토끼").
- 내 사진으로도 만들 수 있어요.
- 여러 상태(기본·수면·산책·식사 등)를 한 번에 만들어 일관된 모습으로 완성해요.

■ 진짜 내 하루에 반응해요
- 걸음 수와 운동(산책·달리기·자전거)을 인식해 캐릭터가 함께 움직여요.
- 수면 시간에는 잠든 모습, 아침엔 기지개 켜는 모습으로.
- 식사 시간, 그리고 맑음·흐림·비·눈 날씨까지 반영돼요.

■ 어디서나 함께
- 홈 화면 위젯으로 캐릭터를 항상 곁에.
- 갤럭시 워치(Wear OS) 타일로 손목에서도 확인.
- 캐릭터와 함께 사진도 찍어요.

■ 건강 데이터는 안전하게
- 걸음·운동·수면 데이터는 상태를 정하는 데에만 쓰이고, 필요한 최소한만 읽어요.

지금 나만의 캐릭터를 만들어 하루를 함께 보내보세요.
```

### 신규 기능 (릴리스 노트, 최대 500자)
```
- 갤럭시 워치(Wear OS) 지원: 손목에서 캐릭터를 확인하는 타일이 추가됐어요.
- 걸음·운동·수면·날씨에 맞춰 캐릭터 모습이 자동으로 바뀝니다.
- 홈 화면 위젯이 모든 크기에서 캐릭터·걸음·날씨를 함께 보여줘요.
```

---

## 2. 스토어 등록 문구 (영어)

### App name (≤30)
```
Withy: Your Character Friend
```

### Short description (≤80)
```
Make your own character that comes alive with your steps, sleep, and weather.
```

### Full description (≤4000)
```
Make your own character and spend the day together.

Withy is a companion app where a character you create lives on your home screen and watch. It changes throughout the day based on your steps, workouts, sleep, and the weather. It wakes up in the morning, walks with you, and falls asleep at night.

■ Create your own character
- Just describe it and AI draws it for you (e.g. "a freckled pink bunny").
- Or create one from your own photo.
- Make many states (idle, sleeping, walking, eating…) at once for a consistent look.

■ Reacts to your real day
- Recognizes steps and workouts (walking, running, cycling).
- Sleeping at night, stretching in the morning.
- Reflects meal times and sunny / cloudy / rainy / snowy weather.

■ With you everywhere
- Home screen widget keeps your character close.
- Wear OS (Galaxy Watch) tile on your wrist.
- Take photos together with your character.

■ Your health data stays private
- Steps, workout, and sleep are used only to decide the character's state, reading the minimum needed.

Create your character now and spend the day together.
```

### Release notes (≤500)
```
- Wear OS (Galaxy Watch) support: a tile to see your character on your wrist.
- Your character now changes automatically with steps, workouts, sleep, and weather.
- The home screen widget shows character, steps, and weather at every size.
```

---

## 3. 그래픽 자산

| 자산 | 규격 | 상태 |
|---|---|---|
| 앱 아이콘 | 512×512 PNG (32-bit) | `icon-512.png` 생성됨 (아래 참고) |
| 피처 그래픽 | 1024×500 PNG/JPG | `feature-graphic.png` 생성됨 |
| 폰 스크린샷 | 최소 2장, 16:9 또는 9:16 | `screenshots-phone/` 5장 |
| Wear 스크린샷 | 최소 1장 (정사각/원형) | `screenshots-wear/` 1장 |

폰 스크린샷 (1080×2400, 실기기 Galaxy S21 캡처):
1. `01-home.png` — 홈: 캐릭터 + 날씨 + 오늘 활동
2. `02-create.png` — AI로 캐릭터 만들기
3. `03-gallery.png` — 상태별 캐릭터 갤러리
4. `04-settings.png` — 수면·식사 시간 설정
5. `05-widget.png` — 홈 화면 위젯

Wear 스크린샷 (Wear OS 5 에뮬레이터):
1. `01-watch-character.png` — 워치에서 캐릭터 + 걸음 + 날씨

---

## 4. 릴리스 빌드 만들기

Wear OS 앱은 폰 앱과 **같은 Play 등록**에 별도 AAB로 올립니다(권장). 두 개를 만들어 같은 앱 리스팅에 업로드하면 Play가 기기에 맞게 배달합니다.

```bash
cd android
# 폰
./build.sh :app:bundleRelease
#   → app/build/outputs/bundle/release/app-release.aab
# 워치
./build.sh :wear:bundleRelease
#   → wear/build/outputs/bundle/release/wear-release.aab
```

> 서명: 아직 릴리스 keystore가 없습니다. Play App Signing을 쓰면 업로드 키만 만들면 됩니다 (아래 체크리스트).

---

## 5. 직접 하셔야 할 것 (사람만 가능)

- [ ] **Play Console 개발자 계정** ($25 1회) 및 앱 생성.
- [ ] **업로드 keystore 생성** + `app/build.gradle.kts`·`wear/build.gradle.kts`에 signingConfig 연결 (또는 Play App Signing 등록). keystore·비밀번호는 커밋 금지.
- [ ] **개인정보처리방침 URL** — 건강 데이터(걸음·운동·수면)를 읽으므로 필수. 무엇을 읽고 어디에 쓰는지(기기 내 상태 결정에만 사용, 서버 전송 없음) 명시.
- [ ] **데이터 보안(Data safety) 설문** — 건강/피트니스 데이터 수집 여부·용도 응답. 사진 생성은 서버(Cloudflare Worker) 경유임을 반영.
- [ ] **콘텐츠 등급 설문**.
- [ ] **Health Connect 권한 선언 심사** — 걸음·운동·수면 읽기 사용 사유 제출(Google 별도 승인 절차).
- [ ] **Wear OS 리뷰** — 워치 앱은 별도 품질 심사가 있을 수 있음. 같은 리스팅에 wear AAB 업로드.
- [ ] **결제(캔디)** — Play Billing 실결제는 파리티 스코프에서 제외(no-op). 실제 판매하려면 Play Billing 연동 + 상품 등록 필요(현재는 리딤코드/무료 1회만).

---

## 6. 참고: 아키텍처(심사 문답용)

- 건강 데이터는 **Health Connect**에서 최소 권한으로 읽어 캐릭터 상태(기본/수면/산책/달리기/자전거/식사/기상)를 정하는 데에만 사용. 서버로 보내지 않음.
- 이미지 생성만 서버(Cloudflare Worker → OpenAI)로 프롬프트/참고사진을 보냄. 생성 결과는 기기에 저장.
- 워치(Wear OS)는 폰이 계산한 상태·이미지를 Data Layer로 받아 **표시만** 함(건강 재수집 없음).
