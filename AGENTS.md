# Paxo — AI 에이전트 작업 규칙

Paxo는 화면 속 문제를 단축키로 캡처하면 AI가 정답과 해설을 알려주는 **macOS 메뉴바 앱**이다.
저장소 이름이 `iOS`지만 iOS 앱이 아니다. 배포 타깃은 macOS 14+.

이 파일은 저장소 전역 규칙이다. 하위 디렉토리에 더 구체적인 `AGENTS.md`가 있고,
에이전트는 트리에서 **가장 가까운 파일**을 읽는다.

- `Paxo/AGENTS.md` — Swift 앱 코드 (밟기 쉬운 지뢰 모음)
- `proxy-vercel/AGENTS.md` — API 프록시 계약

## 셋업

클론 직후 반드시 1회. **이 파일이 없으면 빌드가 실패한다.**

```sh
cp Config/Secrets.example.swift Paxo/Secrets.swift
```

`Paxo/Secrets.swift`는 gitignore 대상이다. 절대 커밋하지 않는다.
템플릿을 `Paxo/` 안에 복사본으로 남기면 `Secrets` 중복 선언으로 빌드가 깨진다.

## 명령

빌드:

```sh
xcodebuild -project Paxo.xcodeproj -scheme Paxo -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

테스트:

```sh
xcodebuild -project Paxo.xcodeproj -scheme Paxo \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

포맷 검사와 적용:

```sh
xcrun swift-format lint --recursive --strict Paxo PaxoTests
xcrun swift-format format --in-place --recursive Paxo PaxoTests
```

## 코드 스타일

- **식별자는 영어, 주석과 사용자 노출 문구는 한국어.** 예외 없다.
- 주석은 *왜*를 적는다. API를 재진술하지 않는다. 밀도는 코드 20줄당 1줄 정도.
- import는 알파벳순. `swift-format`의 `OrderedImports` 규칙으로 CI에서 강제된다.
- 접근 제어는 `private`만 명시하고 `internal`은 생략한다. `public`/`fileprivate`은 쓰지 않는다.
- 모든 참조 타입은 `final`.
- 강제 언래핑(`!`) 금지. 현재 코드베이스에 0개다.
- `print`/`os_log`/`Logger` 추가 금지. 로깅 인프라가 없고, 도입은 별도 논의 대상이다.
- 상태 없는 유틸리티는 case 없는 `enum` 네임스페이스로 만든다 (`Prompts`, `KeychainHelper`).

## 중복을 만들지 않는다

새 유틸리티나 헬퍼를 만들기 전에 **기존 것을 먼저 검색한다.**
비슷한 함수가 이미 있으면 새로 쓰지 말고 그것을 쓰거나 확장한다.
AI 생성 코드가 조용히 중복을 쌓는 것이 이 저장소의 가장 큰 품질 리스크다.

## 커밋과 PR

- 브랜치 접두사: `feat/`, `fix/`, `docs/`, `chore/`, `style/`, `test/`
- 커밋: Conventional Commits 접두사 + **한국어 제목** + `-` 불릿 본문
- **AI 사용 여부를 커밋에 표기하지 않는다.** 초안을 누가 썼든 커밋한 사람이 전적으로 책임진다
- `main` 직접 푸시 금지. PR과 CI 통과가 필수다
- PR을 올리기 전에 빌드와 테스트를 **실제로 돌려서** 통과를 확인한다

## 절대 하지 말 것

- `Paxo.xcodeproj/project.pbxproj`의 파일 목록 수동 편집 — `Paxo/`는 파일시스템 동기화 그룹이라 손댈 필요가 없다
- `Paxo/Secrets.swift` 커밋
- `docs/hansung/` 커밋 — 사업계획서와 신청서, 비공개다
- `node_modules/` 커밋

**이 저장소는 공개다.** 커밋 전에 시크릿이 섞였는지 확인한다.

## 릴리스

전체 절차는 `docs/app-store-submission.md`. 제출 전 함정 3가지만 여기 적는다.

1. `MARKETING_VERSION`이 아직 `0.1.0`이다 — 출시 빌드는 `1.0.0`
2. 공유 스킴의 StoreKit Configuration을 **None**으로 되돌려야 한다. 안 그러면 실제 결제가 동작하지 않는다
3. `DEVELOPMENT_TEAM = L3JLLU88WG`가 실제 배포 인증서의 팀과 일치하는지 확인한다
