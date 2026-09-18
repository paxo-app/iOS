# Paxo

> **macOS 메뉴바 기반 AI 학습 도우미**
> 화면 속 문제를 단축키 한 번으로 캡처하면 AI가 정답과 해설을 제공합니다.


## 1. 핵심 기능 및 사용법

1. **캡처 (Capture)**: 메뉴바 아이콘 클릭 또는 전역 단축키 `⌥⌘S` (설정 변경 가능)
2. **영역 선택 (Selection)**: 문제 영역을 드래그하여 지정 (`Esc` 취소). 설정에서 **전체 화면** 모드 활성화 시 드래그 없이 즉시 캡처.
3. **결과 노출 (Result)**: 정답이 먼저 화면에 표시되고, 이어서 해설이 스트리밍된다.
4. **빠른 채점 모드 (Fast Grading)**: 설정에서 켤 수 있으며, 정답만 크게 강조 표시하고 해설은 "해설 보기" 클릭 시 Lazy-load 방식으로 생성한다 (문제집 셀프 채점용).
5. **토스트 모드 (Toast Mode)**: 정답만 토스트 팝업으로 2~10초간 노출된 후 사라지며 해설은 아예 생성하지 않는다.
6. **결과 패널 위치**: 화면 내 7가지 프리셋 중 원하는 위치를 지정할 수 있다.

## 2. 프로젝트 구조

```text
Paxo/
  PaxoApp.swift            앱 진입점 (MenuBarExtra, Settings)
  AppState.swift           상태 머신 (캡처 → 정답 → 해설, 히스토리 관리)
  HotkeyManager.swift      전역 단축키 `⌥⌘S` 처리 (Carbon, MAS 허용 API)
  DefaultConfig.swift      내장 기본 설정 (프록시 URL 등)
  Secrets.swift            로컬 시크릿 키 관리 (Git 제외됨)
  Capture/
    SelectionOverlay.swift 캡처 영역 지정용 드래그 오버레이
    ScreenCapturer.swift   ScreenCaptureKit 연동 캡처 로직 (App Sandbox 지원)
  AI/
    GeminiService.swift    AI API 연동 (정답 1차 호출 → 해설 2차 호출)
    Prompts.swift          시스템 프롬프트 관리
  UI/                      메뉴바 팝업 / 패널 / 토스트 / 페이월 / 마크다운 렌더러
  Store/                   StoreKit 2 연동 (구독 및 무료 횟수 관리)
  Storage/                 로컬 히스토리 JSON 및 키체인 관리
PaxoTests/                 순수 비즈니스 로직 테스트 (Swift Testing 프레임워크)
Config/                    Info.plist, App Sandbox Entitlements, StoreKit 설정, 시크릿 템플릿
proxy-vercel/              Vercel 기반 주 프록시 (Gemini API 키 보호, 토큰 검증, 사용량 제어)
proxy/                     [Legacy] Cloudflare Worker 기반 백업 프록시
docs/                      아키텍처, 도메인 용어, 의사결정 기록 등 문서화
.claude/skills/            Claude Code 전용 커스텀 스킬
.github/workflows/         CI 파이프라인 설정 (빌드, 테스트, 린트, 금지 파일 검사)

```

## 3. License

이 프로젝트는 [MIT 라이선스](https://www.google.com/search?q=LICENSE&utm_source=gemini)를 따릅니다.
