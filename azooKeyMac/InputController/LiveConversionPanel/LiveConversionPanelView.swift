import Cocoa
import Core

/// 変換パネルの中身。上から文節の列、候補リスト、操作のヒント
final class LiveConversionPanelView: NSView {
    private static let contentInsets = NSEdgeInsets(top: 6, left: 6, bottom: 5, right: 8)
    private static let columnInsets = NSEdgeInsets(top: 3, left: 6, bottom: 4, right: 6)

    private let backgroundView = NSVisualEffectView()
    private let contentStack = NSStackView()
    private let columnsStack = NSStackView()
    /// 候補リストを対象の列の左端にそろえるための入れ物
    private let candidateListContainer = NSView()
    private let candidateListView = LiveConversionCandidateListView()
    private var candidateListLeading: NSLayoutConstraint!
    /// パネルの幅を候補リストの右端まで広げる
    private var candidateListFitsInside: NSLayoutConstraint!
    private let hintLabel = NSTextField(labelWithString: LiveConversionPanelModel.keyHint)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

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
        // 候補リストのほうが広くても列を引き伸ばさない（候補リストを列にそろえる計算が狂うため）
        self.columnsStack.setHuggingPriority(.required, for: .horizontal)

        self.candidateListView.translatesAutoresizingMaskIntoConstraints = false
        self.candidateListContainer.addSubview(self.candidateListView)
        self.candidateListLeading = self.candidateListView.leadingAnchor.constraint(equalTo: self.candidateListContainer.leadingAnchor)

        self.hintLabel.font = .systemFont(ofSize: 10)
        self.hintLabel.textColor = .tertiaryLabelColor
        self.hintLabel.alignment = .right

        self.contentStack.orientation = .vertical
        self.contentStack.alignment = .leading
        self.contentStack.spacing = 2
        self.contentStack.setViews([self.columnsStack, self.candidateListContainer, self.hintLabel], in: .top)
        self.contentStack.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundView.addSubview(self.contentStack)
        self.candidateListFitsInside = self.contentStack.trailingAnchor.constraint(greaterThanOrEqualTo: self.candidateListView.trailingAnchor)

        let insets = Self.contentInsets
        NSLayoutConstraint.activate([
            self.backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.backgroundView.topAnchor.constraint(equalTo: self.topAnchor),
            self.backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.contentStack.leadingAnchor.constraint(equalTo: self.backgroundView.leadingAnchor, constant: insets.left),
            self.contentStack.trailingAnchor.constraint(equalTo: self.backgroundView.trailingAnchor, constant: -insets.right),
            self.contentStack.topAnchor.constraint(equalTo: self.backgroundView.topAnchor, constant: insets.top),
            self.contentStack.bottomAnchor.constraint(equalTo: self.backgroundView.bottomAnchor, constant: -insets.bottom),
            self.candidateListLeading,
            self.candidateListView.trailingAnchor.constraint(equalTo: self.candidateListContainer.trailingAnchor),
            self.candidateListView.topAnchor.constraint(equalTo: self.candidateListContainer.topAnchor),
            self.candidateListView.bottomAnchor.constraint(equalTo: self.candidateListContainer.bottomAnchor),
            self.candidateListView.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            // 操作のヒントは右寄せにする
            self.hintLabel.trailingAnchor.constraint(equalTo: self.contentStack.trailingAnchor)
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

    func update(model: LiveConversionPanelModel) {
        self.columnsStack.arrangedSubviews.forEach {
            self.columnsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        var targetView: NSView?
        for (index, column) in model.columns.enumerated() {
            if index > 0 {
                // 対象の列の両隣の区切り線は消す
                let hidden = column.isTarget || model.columns[index - 1].isTarget
                self.columnsStack.addArrangedSubview(Self.makeSeparator(hidden: hidden))
            }
            let view = Self.makeColumn(column)
            self.columnsStack.addArrangedSubview(view)
            if index == model.targetIndex {
                targetView = view
            }
        }

        if let list = model.candidateList {
            self.candidateListView.update(list: list)
            self.candidateListContainer.isHidden = false
        } else {
            self.candidateListContainer.isHidden = true
        }
        self.candidateListFitsInside.isActive = model.candidateList != nil
        // 大きさが 0 のまま並べると列が詰まって位置を測れないので、中身に合った大きさで並べる
        self.setFrameSize(self.fittingSize)
        self.layoutSubtreeIfNeeded()

        // 候補リストの左端を対象の列の左端にそろえ、三角は列の中央を指す。
        // 列の幅は候補リストに左右されないので、一度並べた位置から決めてもう一度並べる
        if let targetView {
            let frame = targetView.convert(targetView.bounds, to: self.candidateListContainer)
            self.candidateListLeading.constant = frame.minX
            self.candidateListView.arrowX = frame.width / 2
            self.layoutSubtreeIfNeeded()
        }
    }

    private static func makeColumn(_ column: LiveConversionPanelModel.Column) -> NSView {
        let reading = NSTextField(labelWithString: column.reading)
        reading.font = column.isTarget ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 14)
        reading.textColor = if column.isLowConfidence {
            .systemOrange
        } else if column.isTarget {
            .controlAccentColor
        } else {
            .labelColor
        }

        // 本文と同じ文字が二重に見えるのを目立たせないよう、小さく薄く出す
        let surface = NSTextField(labelWithString: column.surface)
        surface.font = .systemFont(ofSize: 11)
        surface.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [reading, surface])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1

        let box = RoundedFillView(
            content: stack,
            fillColor: column.isTarget ? NSColor.controlAccentColor.withAlphaComponent(0.15) : nil,
            cornerRadius: 5,
            insets: Self.columnInsets
        )
        guard column.isLowConfidence else {
            return box
        }
        // 自信の低い列は、下端に警告色の線を引く
        let line = RoundedFillView(content: NSView(), fillColor: .systemOrange, cornerRadius: 0)
        line.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            line.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            line.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 2)
        ])
        return box
    }

    private static func makeSeparator(hidden: Bool) -> NSView {
        let separator = RoundedFillView(content: NSView(), fillColor: hidden ? nil : .separatorColor, cornerRadius: 0)
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
    func show(model: LiveConversionPanelModel, anchor: NSRect) {
        self.panelView.update(model: model)
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
