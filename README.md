# MouseGesture Helper

Karabiner-Elements와 함께 쓰는 최소 macOS helper입니다. Karabiner가 button3를 F20으로 바꾸면 helper가 F20과 포인터 이동을 관찰해 제스처를 판정합니다. 포인터 이벤트는 listen-only tap으로 통과시킵니다. **버튼을 누르지 않은 일반 스크롤은 수정하지 않습니다.** 선택 규칙을 켜면 button4를 누른 동안 수직 휠을 Page Up/Down으로 바꿉니다.

- **button3 짧게 클릭** → macOS에 현재 등록된 Mission Control 단축키
- **button3 300ms 홀드** → macOS에 현재 등록된 App Exposé 단축키
- **button3 + 좌/우 드래그** → macOS 13–26에서 interactive Space swipe
- **button3 + 위/아래 드래그** → macOS 13–26에서 interactive Mission Control/App Exposé gesture
- **일반 마우스 휠 / Trackpad / Magic Mouse 스크롤** → macOS 기본 동작
- **button4 + 수직 휠 (선택 규칙)** → 일반 휠과 같은 방향으로 페이지 단위 이동
- **button4 단독 짧게 클릭 (선택 규칙)** → 뒤로 가기 (`⌘[`)
- **button5 클릭 (선택 규칙)** → 앞으로 가기 (`⌘]`)

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

**System Settings → Privacy & Security → Accessibility**에서 `mousegesture-helper`가 허용되어 있어야 합니다. macOS 27.2에서는 이 항목이 **기기 제어 및 데이터 접근**으로 표시됩니다. helper 바이너리를 업데이트한 뒤 ON 상태인데도 권한 오류가 나면 기존 항목을 제거하고, `+`에서 `~/Library/Application Support/MouseGestureHelper/mousegesture-helper`를 다시 추가해 허용하세요. Input Monitoring 요청이 표시되면 그 권한도 허용한 뒤 다음 명령으로 재시작합니다.

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

## button4 + 휠로 페이지 이동 (선택)

설치 후 Karabiner-Elements의 **Complex Modifications → Add predefined rule**에서 `MouseGesture Helper: button4 + wheel for Page Up/Down`을 활성화합니다. 이 규칙은 `mousegesture-helper-paging.json`으로 설치됩니다.

- button4를 누른 채 휠을 돌리면 일반 스크롤과 같은 방향으로 Page Up/Down을 전송합니다. macOS의 자연스러운 스크롤 설정을 그대로 따르므로 버튼을 눌렀을 때 방향이 바뀌지 않습니다.
- button4를 놓으면 일반 스크롤로 돌아옵니다. 페이지 이동에 사용한 버튼을 놓을 때 단독 클릭을 추가로 보내지 않습니다.
- button4 단독 짧게 클릭(기본 1초 이내)은 `⌘[`로 뒤로 이동합니다. 버튼을 놓는 시점에 전달되며, 휠을 사용한 뒤에는 뒤로 이동하지 않습니다.
- button5 클릭은 `⌘]`로 앞으로 이동합니다. Finder의 폴더 방문 기록과 Chrome/Safari의 페이지 방문 기록 등 이 단축키를 지원하는 앱에서 동작합니다. 앱별 동작은 해당 앱의 단축키 설정을 따릅니다.
- 트랙패드의 연속 스크롤, 수평 휠, 관성 스크롤은 변환하지 않습니다.
- `F19`는 내부 신호로 예약됩니다. 기존 button4/button5 규칙과 겹치면 이 선택 규칙을 활성화하기 전에 중복 규칙을 꺼야 합니다.

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

`MG_HORIZONTAL_SIGN`과 `MG_VERTICAL_SIGN`은 이 단축키 fallback에도 적용됩니다. 기본값(`-1`, `1`)에서는 오른쪽 드래그 → 왼쪽 Space, 왼쪽 드래그 → 오른쪽 Space로 이동하며, 위쪽 드래그 → Mission Control, 아래쪽 드래그 → App Exposé가 실행됩니다. macOS 13–26의 interactive gesture와 같은 방향 설정을 사용합니다.

따라서 fallback도 고정된 `Control+화살표`를 무조건 전송하지 않고, macOS에 현재 등록된 symbolic hot key를 사용합니다. 해당 시스템 단축키가 비활성화되어 있으면 동작하지 않을 수 있습니다. button3 click/hold는 macOS 13–26과 동일하게 동작합니다.

## 테스트

플랫폼 독립 gesture 상태 머신:

```bash
make test
```

스크롤 평활화 코드가 없는지, Karabiner JSON과 plist/shell 문법까지 포함해 검사:

```bash
make check
```

실제 F19/F20/포인터 콜백을 사용한 제스처 방향, Page Up/Down, 일반 휠 통과 회귀 검사 (시스템 입력은 전송하지 않음):

```bash
make mac-test
```

macOS native helper 빌드 (macOS에서만 가능하며 ad-hoc 서명됩니다):

```bash
make mac-build
```

## 삭제

```bash
./scripts/uninstall.sh
```

삭제 후 Karabiner-Elements에서 `MouseGesture Helper: reserve button3 as F20`과 선택한 button4 페이지 이동 규칙도 비활성화하거나 제거하세요. uninstall 스크립트는 설치 파일과 LaunchAgent를 제거하지만 Karabiner 설정 앱의 활성화 상태까지 변경하지는 않습니다.

## Attribution / implementation note

Interactive DockSwipe 이벤트 구성과 mouse-delta → DockSwipe 진행도 아이디어는 Noah Nuebling의 **Mac Mouse Fix** 소스, 특히 `ModifiedDrag.m`, `ModifiedDragOutputThreeFingerSwipe.m`, `TouchSimulator.m`에서 분석한 방식에 기반합니다. 해당 프로젝트는 자체 MMF License를 사용하므로 이 코드를 재배포하거나 제품에 포함한다면 원 프로젝트의 최신 라이선스 조건을 검토하고 파생 사실을 명확히 표시하세요.

이 프로젝트의 DockSwipe 부분은 undocumented macOS event fields에 의존하므로 OS 업데이트에서 깨질 수 있습니다.

### Karabiner F20 주의사항

`button3 -> F20` 항목에 `"repeat": false`를 넣지 마세요. 현재 Karabiner-Elements에서 이 옵션은 F20의 key-up을 button3 release까지 유지하는 것이 아니라 press 시점에 key-down/key-up을 함께 끝내므로, helper가 long-press와 drag 상태를 추적할 수 없게 됩니다. 기본 repeat 동작을 그대로 두면 F20 key-up이 physical button3 release와 함께 전달되고, helper는 중간 auto-repeat key-down을 무시합니다.
