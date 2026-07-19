# TestFlight 노트 — v1.1.0 (빌드 24)

App Store Connect → TestFlight → 이 빌드 → "테스트 정보 / 이 빌드에서 테스트할 사항"에 붙여넣기용.
스토어 업데이트 심사 제출 시 "이 버전의 새로운 기능"에도 아래 첫 블록 사용.

---

## 이 버전의 새로운 기능 (스토어/테스트플라이트 공용)

```
이번 업데이트로 크게 새로워졌어요.

• 캐릭터 클라우드 백업 — 로그인해 두면 폰을 바꾸거나 앱을 다시 설치해도 만든 캐릭터가 갤러리로 돌아와요.
• 새 그린 테마를 입고, 앱 이름 표기를 Withy 로 통일했어요.
• 설정 개편 — 내 캐릭터 설정 바로가기가 생겼고, 권한 버튼이 실제로 동작하며, 취침 리마인더 시간을 직접 고를 수 있어요.
• 잠금화면 위젯의 캐릭터 얼굴이 다시 또렷하게 보여요. 워치 색상 페이스에서도 얼굴이 보여요.
• 단축어 'Withy 캐릭터 새로고침' 추가 — 운동 시작 자동화에 연결하면 앱을 열지 않아도 캐릭터가 바로 바뀌어요.
• 친구 초대 보상이 커졌어요 — 코드를 입력하면 두 사람 모두 캔디 5개를 받아요.
• 곳곳의 안내 문구를 간결하게 다듬었어요.
```

## What's New (English — 스토어 en-US 로컬라이제이션용)

```
A big update for Withy!

• Cloud backup for your characters — sign in and your gallery comes back even after switching phones or reinstalling.
• A fresh green theme, and the app name is now Withy everywhere.
• Settings, reworked — a shortcut to My Character, permission buttons that actually work, and a bedtime reminder you can set to any time.
• Your character's face is crisp again on the Lock Screen widget, and now shows on tinted watch faces too.
• New 'Withy Refresh Character' shortcut — hook it to a workout automation and your character updates instantly without opening the app.
• Bigger invite rewards — enter a friend's code and you both get 5 candies.
• Cleaner, shorter text throughout the app.
```

## 이 빌드에서 테스트할 사항 (테스터 안내)

```
아래를 확인해 주세요:

1) 갤러리 클라우드 백업 (가장 중요)
   - 로그인한 상태로 캐릭터를 만들고, 앱을 삭제 → 재설치 → 로그인해 보세요.
   - 잠시 후 갤러리에 만든 캐릭터들이 돌아오는지. (같은 계정으로 다른 기기 로그인도 동일)

2) 설정
   - 취침 리마인더 시간을 바꾸고 '저장' — 체크 표시와 안내가 뜨는지, 그 시각에 알림이 오는지.
   - 건강/알림 권한 버튼을 눌렀을 때 설정 앱이 열리는지.
   - '내 캐릭터 설정하기'가 설정 안에서 열리는지.

3) 잠금화면 위젯
   - 캐릭터의 눈코입이 보이는지 (예전처럼 또렷하게).
   - 워치를 쓰면: 시계 페이스에 색상을 적용해도 캐릭터 얼굴이 보이는지.

4) 단축어 자동화
   - 단축어 앱 > 자동화 > 운동 시작 트리거에 'Withy 캐릭터 새로고침'을 추가하고,
     워치에서 운동을 시작하면 화면 전환 없이 위젯이 바뀌는지.

문제가 보이면 어느 시각/상황이었는지 함께 알려주세요.
```

---

## 이번 빌드에서 바뀐 것 (개발 참고 — 스토어에는 안 올림)

- 갤러리 클라우드 백업/복원: 서버 /gallery API (D1 gallery_items + R2 withu-gallery) + iOS GallerySyncManager (reconcile, 계정 소유 태깅으로 계정 전환 교차 업로드 차단). 서버 배포 완료 확인됨 (health OK, /gallery 401 fail-closed).
- 설정: 무반응 권한 버튼 → 설정 앱 열기, 리마인더 시간 선택+저장, 액션 버튼 스피너→체크마크 피드백, 내 캐릭터 설정 진입.
- 문구: 22곳 간결화, withu→Withy 101곳 (내부 식별자·저장 키는 불변 — 데이터 호환 유지).
- 색: 연핑크 팔레트 → 그린 (홈 '함께할 캐릭터 생성하기'만 원래 핑크 유지). 온보딩 CTA 진한 그린.
- 위젯/워치: 잠금화면은 불투명 배경 그림만 외곽선(모서리 알파 자동 감지), 워치 틴트는 외곽선+잉크 음영(연한 눈코입 반투명 표시).
- 온보딩: CTA 버튼 위치 전 스텝 고정 (건너뛰기 슬롯 상시 예약).
- App Intent 'RefreshCharacterIntent' (백그라운드, openAppWhenRun=false).

## 올리기 전 체크
- [x] 빌드 번호 증가 (1.1.0 / 23)
- [x] Worker 배포 (갤러리 API — 이 빌드의 백업 기능이 서버에 의존)
- [ ] `withu` scheme, Any iOS Device 로 Archive → 업로드
- [ ] 앱 실행 1회 후 위젯 확인(스케줄이 App Group 에 기록돼야 위젯이 미래 전환 계산)
- [ ] 정식 출시 전: wrangler.toml 의 ALLOW_SANDBOX_IAP="1" 제거 후 재배포 (RELEASE_ACTIVATION.md)
