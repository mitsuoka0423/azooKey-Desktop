import Cocoa
import Core

/// 変換パネルの中身。文節ごとに、上に読み・下に変換結果を並べる
final class LiveConversionPanelView: NSView {
    private static let contentInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
    private static let columnInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

    private let backgroundView = NSVisualEffectView()
    private let columnsStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.wantsLayer = true
        self.backgroundView.material = .popover
        self.backgroundView.blendingMode = .behindWindow
        self.backgroundView.state = .active
        self.backgroundView.wantsLayer = true
        self.backgroundView.layer?.cornerRadius = 8
        self.backgroundView.layer?.masksToBounds = true
        self.backgroundView.layer?.borderWidth = 1
        self.backgroundView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.backgroundView)

        self.columnsStack.orientation = .horizontal
        self.columnsStack.alignment = .top
        self.columnsStack.spacing = 0
        self.columnsStack.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundView.addSubview(self.columnsStack)

        let insets = Self.contentInsets
        NSLayoutConstraint.activate([
            self.backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.backgroundView.topAnchor.constraint(equalTo: self.topAnchor),
            self.backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.columnsStack.leadingAnchor.constraint(equalTo: self.backgroundView.leadingAnchor, constant: insets.left),
            self.columnsStack.trailingAnchor.constraint(equalTo: self.backgroundView.trailingAnchor, constant: -insets.right),
            self.columnsStack.topAnchor.constraint(equalTo: self.backgroundView.topAnchor, constant: insets.top),
            self.columnsStack.bottomAnchor.constraint(equalTo: self.backgroundView.bottomAnchor, constant: -insets.bottom)
        ])
        self.applyBorderColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.applyBorderColor()
    }

    private func applyBorderColor() {
        // CGColor は外観を追わないので、外観が変わるたびに解決し直す
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.backgroundView.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    func update(clauses: [LiveConversionClause]) {
        self.columnsStack.arrangedSubviews.forEach {
            self.columnsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, clause) in clauses.enumerated() {
            if index > 0 {
                self.columnsStack.addArrangedSubview(Self.makeSeparator())
            }
            self.columnsStack.addArrangedSubview(Self.makeColumn(clause))
        }
        self.layoutSubtreeIfNeeded()
    }

    private static func makeColumn(_ clause: LiveConversionClause) -> NSView {
        let reading = NSTextField(labelWithString: clause.reading)
        reading.font = .systemFont(ofSize: 14)
        reading.textColor = .labelColor

        // 本文と同じ文字が二重に見えるのを目立たせないよう、小さく薄く出す
        let surface = NSTextField(labelWithString: clause.surface)
        surface.font = .systemFont(ofSize: 11)
        surface.textColor = .secondaryLabelColor

        let column = NSStackView(views: [reading, surface])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 1
        column.edgeInsets = Self.columnInsets
        return column
    }

    private static func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.fillColor = .separatorColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 32)
        ])
        return separator
    }
}

/// フォーカスを奪わない、変換パネル用のウィンドウ
final class LiveConversionPanelWindow: NSPanel {
    private let panelView = LiveConversionPanelView()
    /// 同じ変換の中で前回決めた上下。確定するか空になったら `nil` に戻す
    private var placement: WindowPositioning.PanelPlacement?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.contentView = self.panelView
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    /// - Parameter anchor: 変換の始まりの行の矩形（スクリーン座標）
    func show(clauses: [LiveConversionClause], anchor: NSRect) {
        self.panelView.update(clauses: clauses)
        let size = self.panelView.fittingSize

        let anchorPoint = CGPoint(x: anchor.minX, y: anchor.midY)
        guard let screen = ScreenLookup.screen(containing: anchorPoint, fallbackWindow: self) else {
            return
        }
        let frame = WindowPositioning.liveConversionPanelFrame(
            anchor: WindowPositioning.Rect(anchor),
            panelSize: WindowPositioning.Size(size),
            screenRect: WindowPositioning.Rect(screen.visibleFrame),
            previousPlacement: self.placement
        )
        self.placement = frame.placement
        self.setFrame(NSRect(origin: frame.origin.cgPoint, size: size), display: true)

        guard !self.isVisible else {
            return
        }
        // 上から下へ短くフェードインする
        self.alphaValue = 0
        self.setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y + 4))
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            self.animator().alphaValue = 1
            self.animator().setFrameOrigin(frame.origin.cgPoint)
        }
    }

    func hide() {
        self.placement = nil
        self.orderOut(nil)
    }
}
