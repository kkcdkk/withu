## 요약

- 작성 예정

## 관련 이슈

- 작성 예정

## 중복 / 포함 관계 확인

- [ ] 열린 이슈와 PR을 확인했다.
- 겹치는 기존 이슈/PR: 작성 예정
- sub-issue 또는 linked issue 필요 여부: 작성 예정
- 작업 브랜치: 작성 예정

## 변경 범위

- 작성 예정

## 검증

- [ ] `xcodebuild -list -project withu.xcodeproj`
- [ ] `xcodebuild -project withu.xcodeproj -scheme withu -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] 시뮬레이터 또는 실기기 실행 확인
- [ ] 해당 없음: 작성 예정

## QA 승인

- [ ] QA 담당 에이전트 또는 사람이 변경사항을 확인했다.
- [ ] QA 승인 댓글 또는 리뷰가 남아 있다.
- [ ] 하네스/저장소 운영 변경 PR이면 작업 에이전트와 별도의 QA subagent가 검증했다.
- [ ] 승인 전에는 머지하지 않는다.

## 머지 기준

- 일반 개발 PR base branch: `develop`
- 배포 PR만 `develop -> main`
- `main` 대상 PR이면 `AGENTS.md`, `CONTRIBUTING.md`, `.github/**` 같은 하네스 파일이
  포함되지 않았는지 확인한다.
- 관련 issue를 해결하는 경우 본문에 `Closes #번호` 또는 `Resolves #번호`를 적는다.
