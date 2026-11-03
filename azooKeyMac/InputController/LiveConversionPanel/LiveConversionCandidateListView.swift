import Cocoa
import Core

/// 対象の文節の真下に吹き出しのように下がる候補リスト
final class LiveConversionCandidateListView: NSView {
    static let arrowHeight: CGFloat = 6
    private static let arrowHalfWidth: CGFloat = 7
    private static let cornerRadius: CGFloat = 6

    private let rowsStack = NSStackView()
    /// 三角の先端の x 座標（このビューの座標）
    var arrowX: CGFloat = 20 {
        didSet {
            self.needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.rowsStack.orientation = .vertical
        self.rowsStack.alignment = .leading
        self.rowsStack.spacing = 0
        // 中身を切り詰めず、候補の幅に合わせてリストを広げる
        self.rowsStack.setClippingResistancePriority(.required, for: .horizontal)
        self.rowsStack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.rowsStack)
        NSLayoutConstraint.activate([
            self.rowsStack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 3),
            self.rowsStack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -3),
            self.rowsStack.topAnchor.constraint(equalTo: self.topAnchor, constant: Self.arrowHeight + 3),
            self.rowsStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -3)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(list: LiveConversionPanelModel.CandidateList) {
        self.rowsStack.arrangedSubviews.forEach {
            self.rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        var rows: [NSView] = list.items.enumerated().map { index, item in
            Self.makeRow(item, isSelected: index == list.selectedIndex)
        }
        if let title = list.moreRowTitle {
            rows.append(Self.makeMoreRow(title))
        }
        rows.forEach(self.rowsStack.addArrangedSubview)
        // 行の幅をそろえ、選択中の背景が端まで届くようにする
        rows.forEach { $0.widthAnchor.constraint(equalTo: self.rowsStack.widthAnchor).isActive = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 0.5, y: 0.5, width: self.bounds.width - 1, height: self.bounds.height - Self.arrowHeight - 1)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.controlBackgroundColor.withAlphaComponent(0.85).setFill()
        bodyPath.fill()
        NSColor.separatorColor.setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()

        // 枠線の色の三角の上に背景色の三角を重ね、枠線が三角の部分だけ途切れて見えるようにする
        let top = body.maxY
        let x = min(max(self.arrowX, Self.cornerRadius + Self.arrowHalfWidth), self.bounds.width - Self.cornerRadius - Self.arrowHalfWidth)
        let outer = NSBezierPath()
        outer.move(to: NSPoint(x: x - Self.arrowHalfWidth, y: top))
        outer.line(to: NSPoint(x: x, y: top + Self.arrowHeight))
        outer.line(to: NSPoint(x: x + Self.arrowHalfWidth, y: top))
        outer.close()
        NSColor.separatorColor.setFill()
        outer.fill()

        let inner = NSBezierPath()
        inner.move(to: NSPoint(x: x - Self.arrowHalfWidth + 1.5, y: top - 1))
        inner.line(to: NSPoint(x: x, y: top + Self.arrowHeight - 1.5))
        inner.line(to: NSPoint(x: x + Self.arrowHalfWidth - 1.5, y: top - 1))
        inner.close()
        NSColor.controlBackgroundColor.setFill()
        inner.fill()
    }

    private static func makeRow(_ item: LiveConversionPanelModel.CandidateItem, isSelected: Bool) -> NSView {
        let text = NSTextField(labelWithString: item.text)
        text.font = .systemFont(ofSize: 13)
        text.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor

        let hint = NSTextField(labelWithString: item.hint)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        hint.alignment = .right

        let stack = NSStackView(views: [text, hint])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.setClippingResistancePriority(.required, for: .horizontal)
        // 意味の手がかりは右寄せにする。どの欄も縮めず、リストの幅を広げる
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        [text, hint].forEach { $0.setContentCompressionResistancePriority(.required, for: .horizontal) }
        return RoundedFillView(
            content: stack,
            fillColor: isSelected ? .controlAccentColor : nil,
            cornerRadius: 4,
            insets: NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        )
    }

    private static func makeMoreRow(_ title: String) -> NSView {
        let key = NSTextField(labelWithString: "Tab")
        key.font = .systemFont(ofSize: 10, weight: .medium)
        key.textColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [key, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.setClippingResistancePriority(.required, for: .horizontal)
        return RoundedFillView(content: stack, fillColor: nil, cornerRadius: 0, insets: NSEdgeInsets(top: 3, left: 6, bottom: 2, right: 6))
    }

}

/// 中身の大きさに余白を足し、角丸の背景を塗るビュー。色は描くたびに解決するので、ライト・ダークに追従する。
/// `NSStackView` の `edgeInsets` は大きさを詰めるときに削られることがあるので、余白はここで取る
final class RoundedFillView: NSView {
    var fillColor: NSColor? {
        didSet {
            self.needsDisplay = true
        }
    }
    private let cornerRadius: CGFloat

    init(content: NSView, fillColor: NSColor?, cornerRadius: CGFloat, insets: NSEdgeInsets = NSEdgeInsets()) {
        self.fillColor = fillColor
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: self.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -insets.bottom)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let fillColor else {
            return
        }
        fillColor.setFill()
        NSBezierPath(roundedRect: self.bounds, xRadius: self.cornerRadius, yRadius: self.cornerRadius).fill()
    }
}
