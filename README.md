# MouseGesture Helper

Karabiner-Elements와 함께 쓰는 최소 macOS helper입니다. Karabiner가 button3를 F20으로 바꾸면 helper가 F20과 포인터 이동을 관찰해 제스처를 판정합니다. 포인터 이벤트는 listen-only tap으로 통과시키며, **스크롤 휠을 전혀 가로채지 않습니다.** 휠은 helper 설치 전과 동일한 macOS 기본 동작을 그대로 사용합니다.

- **button3 짧게 클릭** → macOS에 현재 등록된 Mission Control 단축키
- **button3 300ms 홀드** → macOS에 현재 등록된 App Exposé 단축키
- **button3 + 좌/우 드래그** → macOS 13–26에서 interactive Space swipe
- **button3 + 위/아래 드래그** → macOS 13–26에서 interactive Mission Control/App Exposé gesture
- **마우스 휠 / Trackpad / Magic Mouse 스크롤** → helper가 관여하지 않음, macOS 기본 동작
- **button4 / button5** → 전혀 건드리지 않음

## 왜 Karabiner에서 button3를 F20으로 바꾸나

물리 button3를 Karabiner가 F20 down/up으로 바꾸면 helper가 F20을 내부 신호로 소비할 수 있습니다. 따라서 앱에는 middle-click과 F20이 모두 전달되지 않고, button3의 click/hold/drag 판정이 helper 한 곳에서만 일어나 충돌을 피합니다.

`karabiner/button3-to-f20.json`은 button3만 건드리며 button4/button5와 스크롤에는 아무 설정도 하지 않습니다.

## 설치 / 업데이트

필요 조건: macOS 13 이상, Karabiner-Elements, Xcode Command Line Tools. 이벤트 tap을 만들려면 Accessibility 권한이 필요하며, macOS가 요청하는 경우 Input Monitoring도 허용해야 합니다.

기존 버전 위에 업데이트하는 경우에도 같은 명령을 사용합니다.

```bash
cd mousegesture-helper
./scripts/install.sh
```

설치 스크립트는 helper를 다시 빌드하고 기존 설치를 교체합니다.

- `~/Library/Application Support/MouseGestureHelper/mousegesture-helper`
- `~/Library/LaunchAgents/com.local.mousegesture-helper.plist`
- `~/.config/karabiner/assets/complex_modifications/mousegesture-helper.json`

Karabiner-Elements에서:

1. **Complex Modifications** → **Add predefined rule**
2. `MouseGesture Helper: reserve button3 as F20` 활성화

기존에 같은 rule이 이미 활성화되어 있다면 그대로 두면 됩니다.

**System Settings → Privacy & Security → Accessibility**에서 `mousegesture-helper`가 허용되어 있어야 합니다. helper 바이너리를 업데이트한 뒤 macOS가 기존 권한을 그대로 인정하지 않는 경우에는 다시 ON 상태를 확인하고, Input Monitoring 요청이 표시되면 그 권한도 허용한 뒤 다음 명령으로 재시작합니다.

```bash
launchctl kickstart -k gui/$UID/com.local.mousegesture-helper
```

로그 확인:

```bash
tail -f ~/Library/Logs/MouseGestureHelper.log
```

LaunchAgent의 `RunAtLoad`가 활성화되어 있으므로 정상 설치 후에는 로그인/재부팅 때 helper가 자동 시작됩니다.

## 기존 Karabiner button3 규칙

기존에 button3에 `to_if_alone`/`to_if_held_down`을 설정한 다른 규칙은 **비활성화**해야 합니다. 이 helper에서는 click/hold 판단도 helper가 담당하므로 button3에 활성화된 Karabiner rule은 `button3 -> F20` 하나만 남기는 것을 권장합니다.

## 제스처 튜닝

설정은 `~/Library/LaunchAgents/com.local.mousegesture-helper.plist`의 `EnvironmentVariables`에서 바꿀 수 있습니다.

- `MG_DRAG_THRESHOLD=50`: 설치되는 LaunchAgent의 기본값. button3 gesture가 시작되는 이동 거리(px)
- `MG_HOLD_MS=300`: App Exposé long-press 시간(ms)
- `MG_HORIZONTAL_PROGRESS=1.6`: 좌우 DockSwipe 민감도
- `MG_VERTICAL_PROGRESS=1.0`: 상하 DockSwipe 민감도
- `MG_HORIZONTAL_SIGN=-1`: 좌우 방향이 반대면 `1`로 변경
- `MG_VERTICAL_SIGN=1`: 상하 방향이 반대면 `-1`로 변경

바이너리를 환경변수 없이 직접 실행하면 drag threshold의 코드 기본값은 `7px`입니다. 설치된 LaunchAgent에서는 plist의 값인 `50px`가 적용됩니다. 홀드 시간 전에 threshold를 넘으면 drag가 우선하며, drag 중에는 홀드 동작이 실행되지 않습니다.

수정 후:

```bash
launchctl bootout gui/$UID ~/Library/LaunchAgents/com.local.mousegesture-helper.plist
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.local.mousegesture-helper.plist
```

## macOS 27+

Mac Mouse Fix 소스는 macOS 27부터 기존 CGEvent-field-only DockSwipe가 무시되고 IOHIDEvent 기반 경로가 필요하다고 기록하고 있습니다. 이 버전은 안전하게 macOS 27+에서 interactive DockSwipe를 끄고, 드래그를 놓는 순간 누적된 이동 방향에 따라 다음 shortcut fallback을 사용합니다.

- button3 좌우 드래그 release → macOS의 Space 이동 단축키
- button3 상하 드래그 release → macOS의 Mission Control/App Exposé 단축키

따라서 fallback도 고정된 `Control+화살표`를 무조건 전송하지 않고, macOS에 현재 등록된 symbolic hot key를 사용합니다. 해당 시스템 단축키가 비활성화되어 있으면 동작하지 않을 수 있습니다. button3 click/hold는 macOS 13–26과 동일하게 동작합니다.

## 테스트

플랫폼 독립 gesture 상태 머신:

```bash
make test
```

스크롤 기능이 production code에서 완전히 제거되었는지, Karabiner JSON과 plist/shell 문법까지 포함해 검사:

```bash
make check
```

macOS native helper 빌드 (macOS에서만 가능하며 ad-hoc 서명됩니다):

```bash
make mac-build
```

## 삭제

```bash
./scripts/uninstall.sh
```

삭제 후 Karabiner-Elements에서 `MouseGesture Helper: reserve button3 as F20` rule도 비활성화하거나 제거하세요. uninstall 스크립트는 설치 파일과 LaunchAgent를 제거하지만 Karabiner 설정 앱의 활성화 상태까지 변경하지는 않습니다.

## Attribution / implementation note

Interactive DockSwipe 이벤트 구성과 mouse-delta → DockSwipe 진행도 아이디어는 Noah Nuebling의 **Mac Mouse Fix** 소스, 특히 `ModifiedDrag.m`, `ModifiedDragOutputThreeFingerSwipe.m`, `TouchSimulator.m`에서 분석한 방식에 기반합니다. 해당 프로젝트는 자체 MMF License를 사용하므로 이 코드를 재배포하거나 제품에 포함한다면 원 프로젝트의 최신 라이선스 조건을 검토하고 파생 사실을 명확히 표시하세요.

이 프로젝트의 DockSwipe 부분은 undocumented macOS event fields에 의존하므로 OS 업데이트에서 깨질 수 있습니다.

### Karabiner F20 주의사항

`button3 -> F20` 항목에 `"repeat": false`를 넣지 마세요. 현재 Karabiner-Elements에서 이 옵션은 F20의 key-up을 button3 release까지 유지하는 것이 아니라 press 시점에 key-down/key-up을 함께 끝내므로, helper가 long-press와 drag 상태를 추적할 수 없게 됩니다. 기본 repeat 동작을 그대로 두면 F20 key-up이 physical button3 release와 함께 전달되고, helper는 중간 auto-repeat key-down을 무시합니다.
