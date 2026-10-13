import AppKit

/// 메뉴바 커스텀 뷰 — **`statusItem.view` 로 직접 교체** (PLAN_menubar_nsstatusitem).
///
/// DroidRelay `MenuBarSpeedView` 의 검증된 기하를 그대로 옮겼다.
/// 왜 SwiftUI `Text` 가 아닌가: 문자열 공백으로는 셀 폭을 못박을 수 없다.
/// SF 폰트에서 공백·단위 글리프의 실제 pt 폭이 달라 `6K` ↔ `60B` 처럼 열이 어긋난다
/// (A안 캡처 4배 확대 실측). 필드 단위 고정폭 + 우측 정렬만이 구조적으로 정렬된다.
///
/// ## 열 배치가 왜 이렇게 생겼나 (DroidRelay 실측 인용)
/// - **값마다 열 폭이 달라지면 메뉴바가 출렁인다** → 샘플 문자열(`"1023M"`)로 고정폭을 정한다.
///   `"1023M"` 은 `menuRateAlways` 상한(5자) — 실제 최댓값으로 잡아야 자리수가 늘 때 안 밀린다.
/// - 같은 이유로 **오른쪽 정렬** — 단위가(M/K/G) 붙는 자리만 움직여야 읽는다.
/// - `alignment = .right` 만으로는 **안 먹는다** (DroidRelay 실측) —
///   `attributedStringValue` 에 paragraphStyle 정렬이 없으면 문자열 기본 정렬이 쓰인다.
/// - **9pt 가 핵심** — 줄당 11pt, 2줄이 22pt 로 메뉴바 두께에 딱 들어간다.
final class RelayMenuBarView: NSView {

    // MARK: - 구성요소

    private let iconView = NSImageView()
    /// 심각도 점 — 아이콘 우상단 (메뉴바 앰비언트 신호)
    private let severityDot = NSView()
    private let upArrow = NSImageView()
    private let downArrow = NSImageView()

    /// 출처별 텍스트 필드 — **열 하나에 하나.** 4개라 2줄 × 2열이 된다.
    private let col1Up = NSTextField(labelWithString: "")
    private let col1Down = NSTextField(labelWithString: "")
    private let col2Up = NSTextField(labelWithString: "")
    private let col2Down = NSTextField(labelWithString: "")

    private var onClick: (() -> Void)?
    private var onRightClick: (() -> Void)?

    /// **열 개수** — 최대 2 (온라인 기기). 열이 없으면 그 폭도 0 이 된다.
    private var columns = 0
    /// 설정 `relay.menubarSpeed` — off 면 화살표·필드 전부 숨기고 아이콘만 남긴다.
    private var showSpeed = true

    // MARK: - 규격 (DroidRelay 실측값)

    private static let fontSize: CGFloat = 9
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
    /// 아이콘 — DroidRelay 16pt. RelayConsole 은 심각도 점(7pt)이 함께 붙어 가독성을 위해 18 유지.
    private static let iconSize: CGFloat = 18
    private static let arrowSize: CGFloat = 11
    private static let gap: CGFloat = 2
    private static let dotSize: CGFloat = 7

    /// 열 폭을 정하는 샘플 — **값과 무관하게 고정.** `menuRateAlways` 상한 5자(`1023M`).
    private static let widthSample = "1023M"
    private static var colWidth: CGFloat {
        ceil(NSString(string: widthSample).size(withAttributes: [.font: valueFont]).width) + 2
    }

    // MARK: - 초기화

    init(onClick: @escaping () -> Void, onRightClick: @escaping () -> Void) {
        self.onClick = onClick
        self.onRightClick = onRightClick
        super.init(frame: .zero)

        // 화살표 — SF Symbol template (OS 가 다크/라이트 자동 착색)
        for (v, name) in [(upArrow, "arrow.up"), (downArrow, "arrow.down")] {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: Self.arrowSize, weight: .semibold)) {
                img.isTemplate = true
                v.image = img
            }
            v.imageScaling = .scaleProportionallyDown
            v.isHidden = true          // apply() 전까지 숨김 (빈 화살표 깜빡임 방지)
            addSubview(v)
        }

        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        severityDot.wantsLayer = true
        severityDot.layer?.cornerRadius = Self.dotSize / 2
        severityDot.isHidden = true
        addSubview(severityDot)

        for f in [col1Up, col1Down, col2Up, col2Down] {
            f.isEditable = false
            f.isSelectable = false
            f.isBordered = false
            f.backgroundColor = .clear
            f.alignment = .right          // 속도 열 오른쪽 정렬
            f.isHidden = true             // apply() 전까지 숨김
            addSubview(f)
        }
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - 갱신

    /// 값을 세팅한다. `up`/`down` 은 열 순서(= `menuPickedColumns` 순서) 배열, 길이 0~2.
    func apply(
        icon: NSImage,
        dotColor: NSColor?,
        up: [String],
        down: [String],
        showSpeed: Bool
    ) {
        iconView.image = icon
        if let dotColor {
            severityDot.layer?.backgroundColor = dotColor.cgColor
            severityDot.isHidden = false
        } else {
            severityDot.isHidden = true
        }

        self.showSpeed = showSpeed
        columns = showSpeed ? min(2, max(up.count, down.count)) : 0

        set(col1Up, up.indices.contains(0) ? up[0] : "")
        set(col1Down, down.indices.contains(0) ? down[0] : "")
        set(col2Up, up.indices.contains(1) ? up[1] : "")
        set(col2Down, down.indices.contains(1) ? down[1] : "")

        let arrows = columns > 0
        upArrow.isHidden = !arrows
        downArrow.isHidden = !arrows
        col1Up.isHidden = !arrows || up.count < 1
        col1Down.isHidden = !arrows || down.count < 1
        col2Up.isHidden = columns < 2 || up.count < 2
        col2Down.isHidden = columns < 2 || down.count < 2

        needsLayout = true
        layout()
    }

    /// **오른쪽 정렬을 문자열에 명시해야 한다** (DroidRelay 실측).
    /// `NSTextField.alignment = .right` 만으로는 안 먹는다 — paragraphStyle 로 같이 지정.
    private static let rightStyle: NSParagraphStyle = {
        let st = NSMutableParagraphStyle()
        st.alignment = .right
        return st
    }()

    private func set(_ f: NSTextField, _ v: String) {
        // 같은 값이면 건드리지 않는다 — 매번 대입하면 레이아웃이 흔들린다.
        if f.attributedStringValue.string != v {
            f.attributedStringValue = NSAttributedString(string: v, attributes: [
                .font: Self.valueFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: Self.rightStyle,   // ← 이것이 실제 정렬을 결정한다
            ])
        }
    }

    // MARK: - 레이아웃

    /// ```
    ///  [아이콘●]  ↑     32K    31K
    ///            ↓    212K   128K
    ///            └─ 고정폭 열, 오른쪽 정렬 · 아이콘은 두 줄을 걸친다
    /// ```
    override func layout() {
        super.layout()
        let h = NSStatusBar.system.thickness
        // **줄 높이는 폰트 실제값으로 잰다.** 상수로 두면 시스템 폰트에 따라 넘친다.
        let lineH = Self.valueFont.ascender - Self.valueFont.descender + Self.valueFont.leading
        let baseY = (h - lineH * 2) / 2

        let iconX: CGFloat = 0
        // 아이콘은 두 줄을 걸친다 — 1줄에만 두면 ↑ 줄에만 속한 것처럼 보인다 (DroidRelay 지적).
        iconView.frame = NSRect(x: iconX, y: baseY, width: Self.iconSize, height: lineH * 2)
        // 심각도 점 — 아이콘 우상단 (기존 MenuBarExtra ZStack topTrailing + offset(3,-1) 상당)
        severityDot.frame = NSRect(
            x: iconX + Self.iconSize - Self.dotSize + 3,
            y: baseY + lineH * 2 - Self.dotSize - 1,
            width: Self.dotSize, height: Self.dotSize
        )

        let arrowX = iconX + Self.iconSize + Self.gap
        let col1X = arrowX + Self.arrowSize + Self.gap
        let cw = Self.colWidth

        upArrow.frame = NSRect(x: arrowX, y: baseY + lineH, width: Self.arrowSize, height: lineH)
        downArrow.frame = NSRect(x: arrowX, y: baseY, width: Self.arrowSize, height: lineH)
        col1Up.frame = NSRect(x: col1X, y: baseY + lineH, width: cw, height: lineH)
        col1Down.frame = NSRect(x: col1X, y: baseY, width: cw, height: lineH)

        // 2열은 기기가 있을 때만 — 없으면 폭 0 으로 열 자체가 없다.
        let col2X = col1X + cw + Self.gap
        let show2 = columns > 1
        let totalW = show2 ? col2X + cw + 1 : (columns > 0 ? col1X + cw + 1 : Self.iconSize)
        col2Up.frame = NSRect(x: col2X, y: baseY + lineH, width: show2 ? cw : 0, height: lineH)
        col2Down.frame = NSRect(x: col2X, y: baseY, width: show2 ? cw : 0, height: lineH)

        frame.size = NSSize(width: totalW, height: h)
    }

    // MARK: - 클릭

    /// `statusItem.view` 로 쓰면 **버튼이 없어서** 클릭을 직접 받는다 (DroidRelay 동일).
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }

    // MARK: - 검증

    /// 각 필드가 **자기 폭 안에 값이 들어가는지** — 잘림을 숫자로 본다 (DroidRelay debugGeometry).
    var debugGeometry: [String] {
        let h = NSStatusBar.system.thickness
        let lineH = Self.valueFont.ascender - Self.valueFont.descender + Self.valueFont.leading
        let need = lineH * 2
        func fit(_ f: NSTextField) -> String {
            guard !f.isHidden else { return "숨김" }
            let w = f.attributedStringValue.size().width
            if f.attributedStringValue.string.isEmpty { return "빈칸" }
            return f.frame.width + 1 < w ? "**잘림** (w=\(Int(f.frame.width)) < \(Int(w)))" : "ok"
        }
        return [
            "뷰 프레임   : w=\(Int(frame.width)) h=\(Int(frame.height))",
            "필요 높이   : \(Int(need)) (줄당 \(Int(lineH)) × 2) / 메뉴바 \(Int(h))",
            "잘림(높이)  : " + (need <= h + 0.5 ? "없음" : "**있음**"),
            "열 개수     : \(columns)  showSpeed=\(showSpeed)  열폭 \(Int(Self.colWidth))pt (고정)",
            "정렬 확인   : 필드=\(col1Up.alignment == .right ? "right" : "OTHER")"
                + " 문단=\(Self.rightStyle.alignment == .right ? "right" : "OTHER")"
                + " (둘 다 right 여야 오른쪽 정렬된다)",
            "아이콘 프레임: h=\(Int(iconView.frame.height)) (=\(Int(lineH * 2)) 이면 두 줄)",
            "업   열1    : |\(col1Up.attributedStringValue.string)| \(fit(col1Up))",
            "다운 열1    : |\(col1Down.attributedStringValue.string)| \(fit(col1Down))",
            "업   열2    : |\(col2Up.attributedStringValue.string)| \(fit(col2Up))",
            "다운 열2    : |\(col2Down.attributedStringValue.string)| \(fit(col2Down))",
        ]
    }
}
