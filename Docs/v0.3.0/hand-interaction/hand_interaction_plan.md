# SBrain v0.3.0 — Hand Interaction (네이티브 손 제스처 조작)

## 문서 유형: T3 (계획서)
## 작성일: 2026-03-14
## 상태: 진행 예정

---

## 1. 목표

Mac 내장 카메라(FaceTime 카메라)를 통해 손을 인식하고,
3D Brain Map을 **손 제스처로 직접 조작**할 수 있는 기능을 추가한다.

핵심 원칙:
- 손 입력은 **보조 입력**이다. 마우스/트랙패드 없이도 모든 기능이 동작해야 한다.
- 기존 네이티브 SwiftUI Canvas 3D Brain Map을 **그대로 유지**한다.
- 외부 라이브러리(MediaPipe, Three.js) 없이 **Apple 네이티브 프레임워크**만 사용한다.

---

## 2. 기술 스택

| 구성 요소 | 기술 | 비고 |
|----------|------|------|
| 카메라 캡처 | `AVFoundation` (`AVCaptureSession`) | 내장 카메라 실시간 프레임 |
| 손 인식 | `Vision` (`VNDetectHumanHandPoseRequest`) | macOS 11+, 21개 랜드마크/손 |
| 렌더링 | 기존 SwiftUI `Canvas` | 변경 없음 |
| 제스처 매핑 | 커스텀 `GestureRecognizer` | 랜드마크 → 제스처 상태 변환 |

### Vision Framework 손 랜드마크 (21개/손)

```
                    Tip(4)
                     |
                   DIP(3)
                     |
                   PIP(2)          Tip(8)   Tip(12)  Tip(16)  Tip(20)
                     |               |        |        |        |
                   MCP(1)          DIP(7)  DIP(11)  DIP(15)  DIP(19)
                     |               |        |        |        |
                   CMC(0)          PIP(6)  PIP(10)  PIP(14)  PIP(18)
                      \              |        |        |        |
                       \           MCP(5)  MCP(9)  MCP(13)  MCP(17)
                        \            \       |       /        /
                         --------  WRIST  ---------
```

- Thumb: CMC → MCP → IP → Tip (4개)
- Index ~ Pinky: MCP → PIP → DIP → Tip (각 4개)
- Wrist: 1개

---

## 3. 제스처 매핑 (MVP)

### 4가지 핵심 제스처만 구현

| 제스처 | 인식 방법 | Brain Map 동작 | 우선순위 |
|--------|----------|---------------|---------|
| **Pointing (검지)** | 검지만 펴고 나머지 접힘 | 포인터 이동 (hover) | P0 |
| **Pinch (집기)** | 엄지 Tip ↔ 검지 Tip 거리 < 임계값 | 노드 선택 | P0 |
| **Open Palm (펼친 손)** | 5개 손가락 모두 펴짐 | 카메라 회전 (orbit) | P0 |
| **Victory (브이)** | 검지+중지 펴고 나머지 접힘 | 선택된 노드 열기 | P1 |

### 제스처 판별 로직

```
손가락 펴짐 판별:
  - Tip.y < PIP.y (Vision 좌표계: 아래가 0, 위가 1)
  - 엄지는 Tip.x vs MCP.x 거리로 판별 (좌우 방향)

Pinch 판별:
  - distance(thumbTip, indexTip) < 0.05 (정규화 좌표 기준)
  - 300ms 이상 유지 시 확정 (오작동 방지)

Open Palm 판별:
  - 5개 손가락 모두 펴짐
  - 손바닥 이동 방향 → rotationX/Y 변화량으로 매핑

Pointing 판별:
  - 검지만 펴짐, 나머지 4개 접힘
  - 검지 Tip 좌표 → 화면 좌표로 변환 → hover 대상 탐색
```

---

## 4. 아키텍처

```
┌─────────────────────────────────────────────────┐
│                  SBrain App                      │
│                                                  │
│  ┌──────────────┐    ┌────────────────────────┐  │
│  │ ContentView  │    │    BrainMapView         │  │
│  │  (기존 유지)  │    │    (기존 Canvas 3D)     │  │
│  └──────────────┘    │                          │ │
│                      │  + HandCursorOverlay     │  │
│                      │  + 제스처 → 회전/줌/선택  │  │
│                      └──────────┬───────────────┘  │
│                                 │                  │
│  ┌──────────────────────────────┴───────────────┐  │
│  │          HandTrackingManager                  │  │
│  │  (ObservableObject, @MainActor)               │  │
│  │                                               │  │
│  │  ┌─────────────┐  ┌────────────────────────┐  │  │
│  │  │ CameraService│  │ GestureClassifier     │  │  │
│  │  │ AVCapture    │  │ 랜드마크 → 제스처 상태  │  │  │
│  │  │ Session      │→ │ Pointing/Pinch/Palm/V │  │  │
│  │  └─────────────┘  └────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### 새로 추가되는 파일

| 파일 | 역할 |
|------|------|
| `Services/HandTrackingManager.swift` | 카메라 + Vision 손 인식 + 제스처 분류 통합 관리 |
| `Views/HandCursorOverlay.swift` | 손 포인터 시각화 오버레이 |

### 기존 파일 수정

| 파일 | 변경 내용 |
|------|----------|
| `Views/BrainMapView.swift` | 손 제스처 입력을 회전/줌/선택에 연결 |
| `Views/ContentView.swift` | Hand Tracking 토글 UI 추가 |
| `Info.plist` / Entitlements | 카메라 사용 권한 (`NSCameraUsageDescription`) |

---

## 5. 핵심 컴포넌트 설계

### 5.1 HandTrackingManager

```swift
@MainActor
class HandTrackingManager: ObservableObject {
    // 상태
    @Published var isEnabled = false          // 손 추적 활성화 여부
    @Published var isTracking = false         // 손이 감지되고 있는지
    @Published var gesture: HandGesture = .none
    @Published var pointerPosition: CGPoint?  // 정규화 좌표 (0~1)
    @Published var palmCenter: CGPoint?       // 손바닥 중심
    @Published var palmDelta: CGPoint?        // 프레임 간 이동량
    @Published var confidence: Float = 0

    // 카메라
    private var captureSession: AVCaptureSession?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "hand-tracking")

    // Vision
    private let handPoseRequest = VNDetectHumanHandPoseRequest()

    func start() { ... }   // 카메라 시작 + Vision 요청 준비
    func stop() { ... }    // 카메라 정지 + 리소스 해제
}
```

### 5.2 HandGesture 열거형

```swift
enum HandGesture: Equatable {
    case none           // 손 미감지
    case pointing       // 검지로 가리키기 → hover
    case pinch          // 엄지+검지 집기 → 선택
    case openPalm       // 손바닥 펴기 → 카메라 회전
    case victory        // 브이 → 노드 열기
}
```

### 5.3 BrainMapView 연동

```swift
// 기존 DragGesture와 병렬로 작동
// 손 입력이 활성화되면:
//   - pointing → hoveredNeuronId 업데이트
//   - pinch → 해당 뉴런 선택 (selectFile)
//   - openPalm → rotationX/Y += palmDelta * sensitivity
//   - victory → 선택된 노드 상세 열기
```

### 5.4 HandCursorOverlay

```swift
// Brain Map 위에 오버레이되는 손 포인터 시각화
// - 반투명 원형 커서 (상태별 색상 변경)
//   - pointing: 시안 글로우
//   - pinch: 노란색 수축 애니메이션
//   - openPalm: 큰 반투명 원
//   - victory: 별 모양 이펙트
// - 손 미감지 시 페이드아웃
```

---

## 6. 카메라 권한 및 프라이버시

- `Info.plist`에 `NSCameraUsageDescription` 추가
- 카메라 미리보기는 **표시하지 않음** (손 인식만 사용, 화면에 카메라 영상 노출 없음)
- 사용자가 명시적으로 Hand Tracking을 켤 때만 카메라 활성화
- 설정에서 on/off 토글 제공

---

## 7. 성능 고려사항

| 항목 | 전략 |
|------|------|
| 프레임 처리 | 카메라 30fps, Vision 처리는 별도 시리얼 큐 |
| 메인 스레드 보호 | Vision 처리 결과만 `@MainActor`로 전달 |
| 배터리 | Hand Tracking 비활성 시 카메라 완전 정지 |
| 지연 | 포인터 위치에 exponential smoothing 적용 (α=0.3) |
| 떨림 방지 | deadzone 적용 (이동량 < 0.005 무시) |
| Pinch 오작동 | 300ms dwell time + 거리 임계값 이중 조건 |

---

## 8. 구현 순서

### Phase 0: 기술 검증 (현재)
- [ ] AVCaptureSession + VNDetectHumanHandPoseRequest 동작 확인
- [ ] 21개 랜드마크 좌표 정상 수신 확인
- [ ] 기본 제스처(pointing, pinch) 판별 로직 검증

### Phase 1: HandTrackingManager 구현
- [ ] CameraService: AVCaptureSession 설정, 프레임 캡처
- [ ] Vision 요청: 프레임 → 손 랜드마크 추출
- [ ] GestureClassifier: 랜드마크 → 4가지 제스처 분류
- [ ] Smoothing + Deadzone + Dwell time 적용

### Phase 2: BrainMapView 연동
- [ ] HandCursorOverlay 구현 (손 포인터 시각화)
- [ ] Pointing → hover 연동 (기존 hitTest 재활용)
- [ ] Pinch → 노드 선택 연동
- [ ] Open Palm → 카메라 회전 연동

### Phase 3: UI 및 안정화
- [ ] ContentView에 Hand Tracking 토글 추가
- [ ] 설정: 민감도, dwell time 조정
- [ ] 손 감지/비감지 전환 시 자연스러운 페이드
- [ ] 마우스 입력과의 충돌 방지

---

## 9. 리스크 및 대응

### 카메라 권한 거부
- **대응**: 권한 거부 시 Hand Tracking 버튼 비활성화 + 안내 메시지

### 손 인식 정확도 부족
- **대응**: confidence threshold (0.5 이상만 사용), smoothing으로 떨림 완화

### 성능 저하 (저사양 Mac)
- **대응**: Hand Tracking 자체가 옵션 기능, 카메라 해상도를 640x480으로 제한

### 조명 환경 문제
- **대응**: confidence 값이 낮으면 포인터 투명도 증가로 "불확실함" 시각 표현

---

## 10. 향후 확장

- 양손 인식 (왼손: 카메라 orbit, 오른손: 선택)
- 제스처 커스터마이징 (사용자 설정)
- 카메라 미리보기 미니 창 (디버그/설정용)
- 손가락 개수 기반 줌 (pinch spread)
