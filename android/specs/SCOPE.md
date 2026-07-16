# Android 파리티 범위 (ultracode 대장정)

목표: iOS withu 앱과 동일한 안드로이드 앱. Swift 원본이 진실 — 문구·레이아웃·로직을 그대로 옮긴다.

## 포함 (파리티 대상)
- 홈: 날씨 헤더, 캐릭터 히어로(절차적 모션), 오늘 활동 카드, 버튼 4개, 설정 시트
- 캐릭터 만들기(단건): 상태 선택, 설명+항목별 도우미, 참고사진(갤러리/앨범+정사각 크롭+그대로둘것/바꿀것), 그림체, 캔디 팝업, 결과+버전 이력, 이어서 다듬기, 움직이는 캐릭터(2프레임)
- 여러 모습 만들기(배치): 상태 선택, 기준 모습 승인 플로우, 백그라운드 큐(WorkManager), 완료 알림(탭→결과 화면), 결과 그리드, 개별 바꾸기/재시도, 모두 적용/모두 저장
- 갤러리: 상태별/캐릭터별 폴더, 그리드, 상세(적용/다른자리/저장/배경빼기·있기+이대로저장/다듬기/삭제), 다중 선택
- 내 캐릭터 설정: 이름, 수면 시간+기준 칩, 식사 시간, 상태별 캐릭터 목록
- 상태 자동 결정: CharacterStateResolver 포팅 (시간 기반 + Health Connect 걸음/수면/운동)
- 날씨: Open-Meteo + 위치(반올림 2자리), 날씨 데코
- 캔디(로컬 쿼터): GenerationQuota 포팅, 페이월 UI (Play 결제는 후속 — 구매 버튼은 '준비 중')
- 온보딩 + 사용법 안내
- 홈 위젯(Glance): 캐릭터 표시
- 카메라 합성(CameraX): 캐릭터와 함께 사진

## 제외 (후속)
- Wear OS, Google 로그인(/auth/google), Play Billing 실결제, 배경 생성(날씨 배경 AI)

## 기술 규칙
- Kotlin + Compose(M3), 패키지 com.seoyoung.withu, minSdk 28
- 빌드 검증: ./build.sh :app:assembleDebug (JDK 자동 설정)
- 문구는 iOS Localizable 한국어 원문 그대로 (strings.xml, values-en 은 카탈로그 en 값)
- 서버는 기존 Worker 그대로 (X-Withu-Token, model=gpt-image-2, 마젠타 크로마키)
- 이미지 저장 스키마는 iOS CharacterImageStore 와 동형 (characters/<state>.png, gallery/<uuid>.png + metadata.json)
