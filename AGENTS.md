# 에이전트 작업 규칙

Codex, Claude 등 코딩 에이전트는 이 문서를 `withu` 저장소의 공통 작업
규칙으로 따른다.

## 프로젝트 기준

- Xcode 프로젝트: `withu.xcodeproj`
- 공유 scheme: `withu`
- 앱 소스 루트: `withu/`
- 현재 타깃: iOS 앱만 있음. 테스트 타깃, watchOS 타깃은 아직 없음.

## 기본 작업 규칙

- 작업 시작 전 `git status --short` 로 기존 변경사항을 확인하고, 관련 파일을
  먼저 읽는다.
- 작업 계획, 이슈 생성, 브랜치 생성, 구현을 시작하기 전에 열린 GitHub issue와 PR을
  확인한다. 새 작업의 일부라도 기존 이슈/PR과 겹치거나 포함 관계가 있으면 독립
  작업으로 진행하지 않는다.
- 기존 이슈가 같은 문제를 다루면 새 이슈를 만들지 말고, 기존 이슈에 작업 범위,
  해결 방향, 현재 브랜치를 댓글로 남긴다.
- 큰 이슈의 일부만 맡는 경우에는 sub-issue 또는 linked issue를 만들고 부모 이슈를
  명시한다.
- 사용자가 만든 변경사항을 되돌리거나 덮어쓰지 않는다. 되돌리기가 필요하면
  사용자가 명확히 요청했을 때만 한다.
- 하네스/저장소 운영 작업은 문서, 에이전트 지침, 가벼운 git hygiene 설정에
  한정한다. 이런 작업만 할 때는 `withu.xcodeproj` 또는 앱 소스 파일을 수정하지
  않는다.
- 로컬 signing 설정, provisioning profile, 개인 LAN IP, secret, DerivedData,
  빌드 산출물은 커밋하지 않는다.
- 사용자가 커밋을 요청했을 때는 작고 명확한 커밋을 선호한다. 요청 없이 커밋,
  태그, 머지는 만들지 않는다.

## 한국어 GitHub 운영

- GitHub issue, PR 제목/본문, PR 댓글, 작업 요약, 커밋 메시지는 가능한 한
  한국어로 작성한다.
- 명령어, 브랜치명, 파일명, 에러 원문은 영어 그대로 둬도 된다.
- 사용자가 이해하기 쉽게 "무엇을 바꿨는지", "왜 바꿨는지", "어떻게 검증했는지"를
  짧게 한국어로 남긴다.

## 브랜치 규칙

- `main`: 최종 배포 버전 기준 브랜치.
- `develop`: 개발 완료 후 통합되는 기본 브랜치.
- 기능/수정 작업 브랜치: `task/<짧은-작업명>` 형식을 기본으로 사용한다.
- 연결된 이슈가 있으면 `task/<이슈번호>-<짧은-작업명>`처럼 브랜치명에 이슈 번호를
  포함한다.
- 새 작업 브랜치는 특별한 이유가 없으면 `develop`에서 만든다.
- 일반 개발 PR의 base branch는 `develop`으로 둔다.
- 배포 준비가 끝난 경우에만 `develop -> main` release PR을 만든다.
- `main`으로 가는 release PR에는 하네스/저장소 운영 전용 파일을 포함하지 않는다.
  예: `AGENTS.md`, `.github/`, `CONTRIBUTING.md`.
- 하네스 파일이 `develop`에만 있어야 하는 경우에는 `main`에서 release 브랜치를 만들고
  앱/문서 배포 변경 커밋만 cherry-pick한다.
- 운영자는 GitHub Repository Ruleset을 만들어 `main` 브랜치에 하네스 파일이 들어가는
  push/merge를 막는다. `Restrict file paths` 규칙에 `AGENTS.md`, `CONTRIBUTING.md`,
  `.github/**`를 추가한다.
- ruleset이 없는 동안에는 `main` 대상 PR에서 위 파일들이 diff에 포함되면 병합하지
  않는다.
- 관련 없는 정리는 같은 작업 브랜치에 섞지 않는다. 별도 이슈나 별도 PR로 분리한다.

## PR 및 QA 규칙

- `main` 또는 `develop`에 직접 푸시하지 않는다. 변경사항은 PR로 올린다.
- PR 본문에는 관련 이슈, 중복/포함 관계 확인 결과, 변경 범위, 검증 결과, 남은
  위험을 한국어로 적는다.
- 이슈를 해결하는 PR은 본문에 `Closes #번호` 또는 `Resolves #번호`를 명시한다.
- 하네스/저장소 운영 변경 PR은 반드시 작업 에이전트와 별도의 QA subagent를 두고
  검증한다.
- 하네스 QA subagent는 PR diff, 브랜치 기준, GitHub issue/PR 운영 규칙, 검증
  명령이 실제 문서와 맞는지 확인하고 PR에 한국어 승인 또는 수정 요청을 남긴다.
- 머지는 QA 담당 에이전트 또는 사람이 변경사항과 검증 결과를 승인한 뒤에만 한다.
- QA 승인은 PR 댓글 또는 리뷰로 남긴다. 승인 전에는 머지하지 않는다.
- 긴급 수정처럼 예외가 필요하면 PR 본문이나 댓글에 예외 사유를 한국어로 남긴다.

## 빌드 및 검증

scheme과 타깃 확인:

```bash
xcodebuild -list -project withu.xcodeproj
```

로컬 signing 없이 컴파일만 확인하는 기본 명령:

```bash
xcodebuild -project withu.xcodeproj \
  -scheme withu \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

현재 테스트 타깃은 없다. 테스트 타깃이 생기면 아래 형태의 simulator test 명령을
표준 검증 루트에 추가한다.

```bash
xcodebuild test -project withu.xcodeproj \
  -scheme withu \
  -destination 'platform=iOS Simulator,name=<사용 가능한 시뮬레이터>'
```

카메라 기능은 실제 iPhone이 필요하다. Simulator 빌드는 컴파일과 기본 화면 실행은
검증할 수 있지만, AVFoundation 촬영 플로우 전체를 검증할 수는 없다.

## GitHub Issue 규칙

- 작업 중 의미 있는 저장소/빌드/런타임 오류가 발견되고 같은 작업에서 해결하지
  못하면 GitHub issue를 만든다.
- 문제만 적은 기본 이슈를 만들지 않는다. 이슈에는 배경/문제, 확인 근거, 해결 방향,
  완료 기준을 포함한다.
- 해결 방향은 바로 구현 가능한 수준으로 짧게 적는다. 여러 방법이 있으면 추천안을
  먼저 적고, 정책 이슈는 공식 문서 링크를 근거로 남긴다.
- issue 제목과 본문은 가능한 한 한국어로 쓴다. 재현 명령, 로그 원문, 환경 정보는
  그대로 포함한다.
- 오류가 해결되면 해결 방법과 검증 결과를 한국어 댓글로 남기고 issue를 닫는다.
- 코드나 문서 변경으로 해결한 경우에는 PR을 만들고 issue와 연결한다.
- 코드 변경 없이 재실행/환경 확인으로 해결된 경우에는 "코드 변경 없음"을 댓글에
  명확히 남긴 뒤 닫는다.
- 일시적인 탐색 실수나 이미 해결된 경고는 issue로 만들지 않는다.

issue 생성 예시:

```bash
gh issue create --title "<한국어 오류 요약>" --body "<재현 방법과 로그>"
```
