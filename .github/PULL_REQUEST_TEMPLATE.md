## 요약

- 

## 관련 이슈

- 

## 변경 범위

- 

## 검증

- [ ] `xcodebuild -list -project withu.xcodeproj`
- [ ] `xcodebuild -project withu.xcodeproj -scheme withu -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] 시뮬레이터 또는 실기기 실행 확인
- [ ] 해당 없음: 

## QA 승인

- [ ] QA 담당 에이전트 또는 사람이 변경사항을 확인했다.
- [ ] QA 승인 댓글 또는 리뷰가 남아 있다.
- [ ] 하네스/저장소 운영 변경 PR이면 작업 에이전트와 별도의 QA subagent가 검증했다.
- [ ] 승인 전에는 머지하지 않는다.

## 머지 기준

- 일반 개발 PR base branch: `develop`
- 배포 PR만 `develop -> main`
- 관련 issue를 해결하는 경우 본문에 `Closes #번호` 또는 `Resolves #번호`를 적는다.
