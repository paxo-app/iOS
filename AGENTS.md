# Paxo — AI 에이전트 작업 규칙

> **작업 시작 전 반드시 `git pull`.**

Paxo는 화면 속 문제를 단축키로 캡처하면 AI가 정답과 해설을 알려주는 **macOS 메뉴바 앱**이다.
저장소 이름이 `iOS`지만 iOS 앱이 아니다. 배포 타깃은 macOS 14+.

본 문서는 저장소의 전역 규칙(Global Rule)을 정의한다. 
하위 디렉터리에 위치한 AGENTS.md가 우선 적용되며, AI 에이전트는 작업 중인 위치에서 가장 가까운 규칙 파일을 참조해야 한다.

- `Paxo/AGENTS.md` — Swift 앱 코드 컨벤션 및 주요 주의사항 (Anti-patterns)
- `proxy-vercel/AGENTS.md` — API 프록시 서버 스펙(Contract)

공통 참조 문서:

- `docs/architecture.md` — 앱 ↔ 프록시 ↔ Gemini ↔ StoreKit 시스템 구성도
- `docs/domain.md` — 핵심 도메인 기능 및 과금 관련 용어 사전
- `docs/decisions.md` — 팀의 주요 기술적 결정 사항

## 1. 초기 설정 (Setup)

저장소 클론 직후 반드시 1회 실행해야 한다.

```sh
cp Config/Secrets.example.swift Paxo/Secrets.swift
```

- `Paxo/Secrets.swift`는 gitignore 대상이다. 절대 커밋하지 않는다.
- 템플릿 파일(Secrets.example.swift)을 Paxo/ 디렉터리 내부에 복사본으로 남겨둘 경우, Secrets 구조체 중복 선언(Duplicate declaration) 오류로 인해 빌드가 깨지므로 주의한다.

## 2. 주요 명령어 (Commands)

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

## 3. 코드 스타일 및 컨벤션

- 명명 규칙: 모든 식별자(변수, 함수, 클래스 등)는 영어로, 주석과 사용자 노출 UI 문구는 한국어로 작성한다. 예외는 허용하지 않는다.
- 주석: 코드의 '동작'을 그대로 설명하지 않고 '의도(Why)'를 작성한다. 주석 밀도는 코드 20줄당 1줄 내외로 유지한다.
- Import 정렬: 알파벳순으로 정렬한다. `swift-format`의 `OrderedImports` 규칙에 의해 CI 파이프라인에서 강제(Enforce)된다.
- 접근 제어자: private만 명시적으로 작성하고 `internal은` 생략한다. `public` 및 `fileprivate`은 사용하지 않는다.
- 참조 타입: 모든 참조 타입(Class)은 `final`로 선언한다.
- 안전성: 강제 언래핑(`!`)은 엄격히 금지한다.
- 로깅: `print`, `os_log`, `Logger` 등의 추가를 금지한다. 현재 로깅 인프라가 없으며, 시스템 도입은 추후 별도로 논의한다.
- 유틸리티 객체: 상태(State)를 가지지 않는 유틸리티 함수 묶음은 case가 없는 `enum` 네임스페이스를 활용해 구현한다. (예: `Prompts`, `KeychainHelper`)

## 4. 중복 코드 생성 방지 (DRY)

신규 유틸리티나 헬퍼 함수를 작성하기 전, 반드시 기존에 구현된 코드를 먼저 검색한다.
유사한 로직이 존재한다면 새로 작성하지 않고 기존 코드를 재사용하거나 확장한다. AI 에이전트가 코드베이스를 파악하지 못하고 조용히 중복 코드를 쌓아 올리는 것은 본 프로젝트의 가장 큰 품질 리스크다.

## 5. 브랜치 전략 및 PR 규칙

- 브랜치 네이밍: `feat/`, `fix/`, `docs/`, `chore/`, `style/`, `test/` 접두사를 사용한다.
- 커밋 메시지: `Conventional Commits 접두사 + 한국어 요약 제목 + (필요시) '-' 불릿을 활용한 본문` 형태로 작성한다.
- 책임 소재: 커밋 메시지에 AI 사용 여부를 표기하지 않는다. 코드의 초안 작성자와 무관하게, 해당 코드를 커밋한 담당자가 결과물에 대한 모든 책임을 진다.
- 워크플로우: 기능 개발 브랜치는 `develop`에서 분기하며, PR 또한 `develop`을 타깃으로 생성한다 (Squash Merge). `main` 브랜치는 릴리스용 PR만 수용한다 (Regular Merge).
- 직접 푸시 금지: `develop` 및 `main` 브랜치에 대한 Direct Push를 금지한다. 반드시 PR 생성 후 CI를 통과해야 한다.
- 사전 검증: PR을 생성하기 전, 로컬 환경에서 직접 빌드 및 테스트를 실행하여 정상 동작을 확인해야 한다.

## 6. 엄격한 금지 사항 (Do Not's)

- `Paxo.xcodeproj/project.pbxproj`의 파일 목록 수동 편집 — `Paxo/`는 파일시스템 동기화 그룹이라 손댈 필요가 없다
- `Paxo/Secrets.swift` 커밋
- `docs/hansung/` 커밋 — 사업계획서와 신청서, 비공개다
- `docs/private/` 커밋 — 비공개 저장소 `paxo-app/internal`의 clone이다. 내용을 공개 저장소로 옮기지 않는다
- `node_modules/` 커밋

- `Paxo.xcodeproj/project.pbxproj` 수동 편집 금지: `Paxo/` 디렉터리는 파일 시스템과 자동 동기화되도록 설정되어 있으므로 프로젝트 파일을 수동으로 수정할 필요가 없다.
- `Paxo/Secrets.swift` 커밋 금지.
- `docs/hansung/` 커밋 금지: 비공개 사업계획서 및 신청서가 포함되어 있다.
- `docs/private/` 커밋 금지: 사내 비공개 저장소(`paxo-app/internal`)의 서브모듈/클론본이다. 보안 내용을 퍼블릭 레포지토리로 유출하지 않는다.
- `node_modules/` 커밋 금지.

> 주의: 현재 저장소는 퍼블릭(Public) 저장소다. 커밋 전 API 키, 토큰 등 시크릿 정보가 포함되지 않았는지 반드시 교차 검증한다.

## 릴리스 체크리스트

전체 배포 프로세스는 사내 비공개 저장소 문서(`docs/private/app-store-submission.md`)를 따른다. 배포 직전 가장 빈번하게 발생하는 3가지 크리티컬 이슈를 아래에 명시한다.

- 버전 확인: `MARKETING_VERSION`이 0.1.0 상태로 남아있는지 확인한다. 실제 출시 빌드는 1.0.0 (또는 그 이상)이어야 한다.

- StoreKit 설정 복구: 공유 스킴(Scheme)에 설정된 StoreKit Configuration을 반드시 None으로 원복해야 한다. 해당 설정이 남아있으면 프로덕션 환경에서 실제 결제가 동작하지 않는다.

- 인증서 팀 매칭: 프로젝트 세팅의 `DEVELOPMENT_TEAM = L3JLLU88WG` 값이 실제 배포용 App Store Connect 팀 ID와 정확히 일치하는지 확인한다.