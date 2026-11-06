# 풀이권 출시 안내

이 변경은 앱·프록시 코드를 준비한다. 운영 판매를 시작하려면 App Store Connect 상품 등록과
심사, 프록시 선배포, App Store 서버 알림 설정이 필요하다. 로컬 `.storekit` 파일을 바꾸는 것만으로
실제 판매 상품이 생성되지는 않는다.

## 상품 등록

네 상품 모두 **소모성(Consumable)**으로 등록한다. 한국 스토어 목표 가격은 아래와 같으며,
다른 스토어의 가격은 App Store Connect에서 확인한다. 앱의 구매 버튼은 StoreKit의 `displayPrice`를 표시한다.

| 상품 ID | 제공량 | 한국 가격 |
| --- | ---: | ---: |
| `com.hyeseong.Paxo.credits.30` | 30회 | 990원 |
| `com.hyeseong.Paxo.credits.100` | 100회 | 2,900원 |
| `com.hyeseong.Paxo.credits.500` | 500회 | 13,900원 |
| `com.hyeseong.Paxo.credits.1000` | 1,000회 | 26,900원 |

등록 전 App Store Connect의 한국(KOR) 가격표에서 각 금액에 해당하는 실제 가격 포인트를 확인한다.
API를 사용하면 `GET /v2/inAppPurchases/{id}/pricePoints?filter[territory]=KOR&include=territory&limit=200`의
전체 페이지에서 `customerPrice`를 대조한다. 특히 990원 지원 여부를 추정하지 않으며, 지원하지 않는 금액을
임의로 다른 가격으로 바꾸지 않는다. [Apple 가격 설정 안내](https://developer.apple.com/documentation/appstoreconnectapi/managing-in-app-purchases)

상품 설명에는 정답과 같은 풀이의 해설 포함, 무료분 우선 사용, 만료 없음, 자동 결제 없음,
Paxo 로그인 계정에 적립된다는 점을 명시한다. AI 유사 문제·플래시카드·새 Pro 멤버십은 현재 혜택에 포함하지 않는다.

## 배포와 전환

1. 기존 월간·연간 구독 상품의 신규 판매 및 갱신 중단 절차를 App Store Connect에서 확인한다.
   앱에서 구매 버튼을 없애도 기존 자동 갱신은 자동으로 해지되지 않는다. 이미 결제한 이용 기간은
   서버의 기존 구독 검증 경로로 보장한다.
2. 네 소모성 상품과 가격·현지화·심사 정보를 등록한다. 첫 소모성 상품은 기존 구독의 승인 여부와 별개로
   새 macOS 앱 버전과 함께 심사에 제출해야 한다.
   [Apple 심사 제출 안내](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)
3. 새 API·지갑 저장 방식을 검증한 뒤 운영 프록시를 앱보다 먼저 배포한다.
4. App Store Connect의 Production 및 Sandbox 서버 알림 URL을 모두
   `https://api.paxo.co.kr/store/notifications`로 설정하고 V2를 선택한다. TestFlight의 Release 앱도 운영 API를
   사용하므로 Sandbox 환불 알림이 같은 서버의 Sandbox 지갑에 도착해야 한다. Sandbox URL을 Preview 프록시로
   지정하면 운영 서버에 적립된 TestFlight 잔액에 환불이 반영되지 않는다. 각 환경에서 Apple 테스트 알림을 요청하고
   전달 성공을 확인한다.
   [Apple 알림 URL 설정](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications/),
   [테스트 알림 안내](https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications)
5. Sandbox 결제·정답 차감·환불·환불 취소·앱 재실행 시 미완료 거래 처리를 검증한다.
   Sandbox와 Production의 지갑·잔액 버전은 분리하며, 다른 환경의 잔액을 합산하지 않는다.
6. 운영 릴리스의 StoreKit Configuration이 None인지 확인한 뒤 앱을 제출한다.
   서버 API가 활성화되고 App Store 상품을 조회할 수 있어야 구매 버튼이 나타난다.

Apple 계정 키·로그인 정보는 문서나 PR에 기록하지 않는다. 기존 환경 변수를 재사용한다.

## 잔액과 차감

- `remainingToday`: 매일 오전 6시(Asia/Seoul)에 새로 제공되는 무료 2회. 기존 구독의 유효 기간에는 100회.
- `creditBalance`: 만료 없는 충전 잔량. 일일 제공량을 먼저 사용하고 정답 생성 성공 시 1회 차감한다.
- `creditRevision`: 충전·유료 차감·환불로 잔액이 바뀔 때 증가한다. 앱은 같은 계정·환경의 오래된 응답을 무시한다.
- 같은 풀이의 해설에는 추가 차감하지 않는다. 저장된 기록을 다시 보는 데에도 풀이권이 들지 않는다.
- 동시 요청은 서버에서 예약하며, 실패한 생성의 예약은 해제한다. 별도의 유료 일일 상한은 없다.
- 앱은 서버가 구매를 검증해 적립한 뒤에만 StoreKit 거래를 `finish()`한다. 응답이 유실되면 같은 거래를 재전송해
  중복 적립 없이 완료할 수 있다.
- 지갑과 거래 중복 방지 기록에는 TTL을 두지 않는다. 30일 로그인 세션 만료와 충전 잔량 보존은 별개다.
- 환불은 Apple이 서명한 알림과 최신 거래 상태를 확인해 한 번만 반영한다. 이미 사용한 풀이권을 환불하면
  내부 부족분은 이후 충전에서 상계하며 화면 잔액은 0 미만으로 표시하지 않는다.
- 계정 삭제는 남은 풀이권도 삭제한다. 삭제 전 안내하며, 같은 구매를 다시 적립하지 않도록 최소 거래 검증 기록은 유지한다.

## 확인할 시나리오

무료 2회를 먼저 사용한 뒤 유료 잔량이 줄어드는지, 오전 6시에 충전 잔량이 유지되는지,
중복 결제 전달·동시 마지막 풀이·실패 재시도에서 중복 차감이 없는지 확인한다.
구매 응답 대기 중 로그아웃하거나, 풀이 응답 대기 중 충전해도 이전 계정·이전 버전 잔액이 덮이지 않아야 한다.
환불 알림이 중복되거나 순서가 바뀌어도 최신 Apple 거래 상태를 따라야 한다.

로컬 `Config/Paxo.storekit`은 상품 표시와 StoreKit 구매 UI용이다. Xcode 로컬 서명은 Apple 운영·Sandbox 서명과
다르므로 서버 검증을 우회하지 않는다. 전체 적립 경로는 Sandbox/TestFlight의 실제 서명 거래로 검증한다.

참고: [미완료 거래 처리](https://developer.apple.com/documentation/storekit/transaction/unfinished),
[App Store Server API](https://developer.apple.com/documentation/appstoreserverapi),
[생성형 AI 충전 상품 정책](https://developer.apple.com/in-app-purchase/expiring-consumables/).
