---
name: release-check
description: App Store 제출 전 검사. 버전 번호, 서명 팀, StoreKit 설정, APP_TOKEN, 번들 내용물을 순서대로 확인한다. 제출·아카이브·릴리스 준비를 말할 때 쓴다.
---

# 제출 전 검사

전체 절차는 비공개 저장소의 `docs/private/app-store-submission.md`다 (`paxo-app/internal`). 이 스킬은 **코드에서 기계적으로 확인 가능한 것**만 본다.

## 1. 버전

```sh
grep -n "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" Paxo.xcodeproj/project.pbxproj
```

`MARKETING_VERSION`이 `0.1.0`이면 아직 출시 버전이 아니다. 사용자에게 올릴 값을 물어본다.
재제출이라면 `CURRENT_PROJECT_VERSION`도 올려야 한다.

## 2. StoreKit 설정 — 가장 흔한 사고

```sh
grep -n "StoreKitConfigurationFileReference" Paxo.xcodeproj/xcshareddata/xcschemes/Paxo.xcscheme
```

**출시 아카이브 전에는 반드시 제거하거나 None으로 바꿔야 한다.** 남아 있으면 실제 결제가 동작하지 않는다.
공유 스킴이라 팀 전체에 영향을 준다.

## 3. 서명 팀

```sh
grep -n "DEVELOPMENT_TEAM" Paxo.xcodeproj/project.pbxproj
security find-identity -v -p codesigning
```

`DEVELOPMENT_TEAM` 값과 배포 인증서의 팀 ID가 다르면 아카이브가 실패한다.
배포용(Apple Distribution) 인증서가 아예 없으면 그것부터 만들어야 한다.

## 4. 프록시 토큰

```sh
npx vercel env ls
```

`APP_TOKEN`이 프로덕션에 설정돼 있는지 확인한다. 설정 순서를 지키지 않으면 기존 앱이 401을 맞는다.
순서는 `proxy-vercel/AGENTS.md` 참고.

## 5. 번들 내용물

```sh
xcodebuild -project Paxo.xcodeproj -scheme Paxo -configuration Release \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

빌드된 `Paxo.app`에 내부 문서나 시크릿이 들어가지 않았는지 확인한다.

```sh
find <경로>/Paxo.app -iname '*.md' -o -iname '*.swift'
```

## 6. 빌드와 테스트

```sh
xcodebuild -project Paxo.xcodeproj -scheme Paxo -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

## 보고 형식

각 항목을 통과/실패로 표시하고, **실패한 것만** 어떻게 고치는지 설명한다.
사용자 승인 없이 버전 번호나 스킴을 고치지 않는다.
