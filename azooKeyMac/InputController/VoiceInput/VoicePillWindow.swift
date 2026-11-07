import Cocoa
import Core

/// 聞き取りピル（VoicePill）の色
private enum VoicePillColor {
    static let red = NSColor(srgbRed: 0xE5 / 255, green: 0x34 / 255, blue: 0x2B / 255, alpha: 1)
    static let gray = NSColor(srgbRed: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255, alpha: 1)
    static let orange = NSColor(srgbRed: 0xC9 / 255, green: 0x69 / 255, blue: 0x0A / 255, alpha: 1)
    static let failureText = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xF0 / 255, green: 0xA0 / 255, blue: 0x50 / 255, alpha: 1)
            : NSColor(srgbRed: 0x7A / 255, green: 0x3E / 255, blue: 0x04 / 255, alpha: 1)
    }
}

/// マイク（`VoicePill.Mic`）。色の付いた丸に白いマイク。聞いているあいだは輪が広がって消える
private final class VoicePillMicView: NSView {
    static let diameter: CGFloat = 20
    private static let pulseKey = "pulse"

    private let pulseLayer = CALayer()
    private let circleLayer = CALayer()
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        let bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        for layer in [self.pulseLayer, self.circleLayer] {
            layer.frame = bounds
            layer.cornerRadius = Self.diameter / 2
            self.layer?.addSublayer(layer)
        }
        self.pulseLayer.opacity = 0
        self.imageView.frame = bounds.insetBy(dx: 4.5, dy: 4.5)
        self.imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView.contentTintColor = .white
        self.addSubview(self.imageView)
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: Self.diameter),
            self.heightAnchor.constraint(equalToConstant: Self.diameter)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(mic: VoicePillModel.Mic, isPulsing: Bool) {
        let color: NSColor = switch mic {
        case .listening: VoicePillColor.red
        case .finishing: VoicePillColor.gray
        case .failed: VoicePillColor.orange
        }
        let symbol = mic == .failed ? "mic.slash.fill" : "mic.fill"
        self.imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.circleLayer.backgroundColor = color.cgColor
        self.pulseLayer.backgroundColor = color.cgColor
        CATransaction.commit()

        let hasPulse = self.pulseLayer.animation(forKey: Self.pulseKey) != nil
        if isPulsing, !hasPulse {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 1.9
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.55
            opacity.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, opacity]
            group.duration = 1.2
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.repeatCount = .infinity
            self.pulseLayer.add(group, forKey: Self.pulseKey)
        } else if !isPulsing, hasPulse {
            self.pulseLayer.removeAnimation(forKey: Self.pulseKey)
        }
    }
}

/// 声の揺れ（`VoicePill.Level`）。3 本の棒
private final class VoicePillLevelView: NSView {
    private static let barWidth: CGFloat = 3
    private static let spacing: CGFloat = 2
    private static let height: CGFloat = 14
    /// 動きを減らす設定で、声があるときに見せる固定の高さ
    private static let staticLevel = 0.6

    private let bars = (0..<3).map { _ in CALayer() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        for bar in self.bars {
            bar.cornerRadius = 1.5
            self.layer?.addSublayer(bar)
        }
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: Self.barWidth * 3 + Self.spacing * 2),
            self.heightAnchor.constraint(equalToConstant: Self.height)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(level: VoicePillModel.Level, animates: Bool) {
        let heights: [Double]
        let color: NSColor
        switch level {
        case .silent:
            heights = VoiceLevel.barHeights(0)
            color = VoicePillColor.gray
        case .voice(let value):
            heights = VoiceLevel.barHeights(animates ? value : Self.staticLevel)
            color = VoicePillColor.red
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animates ? 0.08 : 0)
        CATransaction.setDisableActions(!animates)
        for (index, bar) in self.bars.enumerated() {
            let height = CGFloat(heights[index])
            bar.backgroundColor = color.cgColor
            bar.frame = CGRect(
                x: CGFloat(index) * (Self.barWidth + Self.spacing),
                y: (Self.height - height) / 2,
                width: Self.barWidth,
                height: height
            )
        }
        CATransaction.commit()
    }
}

/// 止め方（`VoicePill.Keys`）。「⌃⇧D 確定 ・ esc 取消」。キーは小さな枠で囲む
private final class VoicePillKeysView: NSStackView {
    private let commitKey = VoicePillKeysView.makeKeyCap()
    private let commitLabel = VoicePillKeysView.makeText()
    private let cancelKey = VoicePillKeysView.makeKeyCap()
    private let cancelLabel = VoicePillKeysView.makeText()

    init() {
        super.init(frame: .zero)
        self.orientation = .horizontal
        self.alignment = .centerY
        self.spacing = 3
        self.setViews([self.commitKey, self.commitLabel, self.cancelKey, self.cancelLabel], in: .leading)
        self.setCustomSpacing(4, after: self.commitLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(keys: VoicePillModel.Keys) {
        (self.commitKey.subviews.first as? NSTextField)?.stringValue = keys.commitKey
        self.commitLabel.stringValue = "\(keys.commitLabel) ・"
        (self.cancelKey.subviews.first as? NSTextField)?.stringValue = keys.cancelKey
        self.cancelLabel.stringValue = keys.cancelLabel
    }

    private static func makeText() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func makeKeyCap() -> NSView {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 10.5)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let box = NSView()
        box.wantsLayer = true
        box.layer?.borderWidth = 1
        box.layer?.cornerRadius = 4
        box.layer?.borderColor = NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.3).cgColor
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 0),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: 0)
        ])
        return box
    }
}

/// 聞き取りピルの中身。左からマイク、状態の文言、声の揺れ（または止め方）
private final class VoicePillView: NSView {
    private let backgroundView = NSVisualEffectView()
    private let stack = NSStackView()
    private let micView = VoicePillMicView()
    private let label = NSTextField(labelWithString: "")
    private let levelView = VoicePillLevelView()
    private let keysView = VoicePillKeysView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.backgroundView.material = .popover
        self.backgroundView.blendingMode = .behindWindow
        self.backgroundView.state = .active
        self.backgroundView.wantsLayer = true
        self.backgroundView.layer?.masksToBounds = true
        self.backgroundView.layer?.borderWidth = 1
        self.backgroundView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.backgroundView)

        self.label.font = .systemFont(ofSize: 12, weight: .semibold)
        self.label.lineBreakMode = .byTruncatingTail

        self.stack.orientation = .horizontal
        self.stack.alignment = .centerY
        self.stack.spacing = 8
        self.stack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 12)
        self.stack.setViews([self.micView, self.label, self.levelView, self.keysView], in: .leading)
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundView.addSubview(self.stack)

        NSLayoutConstraint.activate([
            self.backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.backgroundView.topAnchor.constraint(equalTo: self.topAnchor),
            self.backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.stack.leadingAnchor.constraint(equalTo: self.backgroundView.leadingAnchor),
            self.stack.trailingAnchor.constraint(equalTo: self.backgroundView.trailingAnchor),
            self.stack.topAnchor.constraint(equalTo: self.backgroundView.topAnchor),
            self.stack.bottomAnchor.constraint(equalTo: self.backgroundView.bottomAnchor),
            self.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.backgroundView.layer?.cornerRadius = self.bounds.height / 2
    }

    func update(model: VoicePillModel) {
        self.micView.update(mic: model.mic, isPulsing: model.isPulsing)
        self.label.stringValue = model.label
        self.label.textColor = switch model.mic {
        case .listening: .labelColor
        case .finishing: .secondaryLabelColor
        case .failed: VoicePillColor.failureText
        }
        if let level = model.level {
            self.levelView.isHidden = false
            self.levelView.update(level: level, animates: model.animatesLevel)
        } else {
            self.levelView.isHidden = true
        }
        if let keys = model.keys {
            self.keysView.isHidden = false
            self.keysView.update(keys: keys)
        } else {
            self.keysView.isHidden = true
        }
        let borderColor: NSColor = model.mic == .failed ? VoicePillColor.orange : .separatorColor
        self.backgroundView.layer?.borderColor = borderColor.cgColor
    }
}

/// フォーカスを奪わない、聞き取りピル用のウィンドウ。変換パネルと同じ位置の決め方で出す
final class VoicePillWindow: NSPanel {
    private let pillView = VoicePillView()
    private var placement: WindowPositioning.PanelPlacement?
    /// 消える途中で出し直したときに、消す処理を取り消すための番号
    private var visibilityGeneration = 0
    private var isHiding = false

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
        self.contentView = self.pillView
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    /// - Parameter anchor: 入力位置の行の矩形（スクリーン座標）
    func show(model: VoicePillModel, anchor: NSRect) {
        self.pillView.update(model: model)
        self.pillView.layoutSubtreeIfNeeded()
        let size = self.pillView.fittingSize

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

        let wasHiding = self.isHiding
        self.visibilityGeneration += 1
        self.isHiding = false
        if self.isVisible, !wasHiding {
            if self.frame.size != size || self.frame.origin != frame.origin.cgPoint {
                self.setFrame(NSRect(origin: frame.origin.cgPoint, size: size), display: true)
                self.invalidateShadow()
            }
            return
        }
        // 変換パネルと同じく、上から下へ短くフェードインする
        self.setFrame(NSRect(origin: NSPoint(x: frame.origin.x, y: frame.origin.y + 4), size: size), display: true)
        self.alphaValue = 0
        self.orderFront(nil)
        self.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            self.animator().alphaValue = 1
            self.animator().setFrameOrigin(frame.origin.cgPoint)
        }
    }

    /// 0.15 秒で薄くして消す
    func hide(animated: Bool = true) {
        self.placement = nil
        guard self.isVisible, !(animated && self.isHiding) else {
            return
        }
        self.visibilityGeneration += 1
        let generation = self.visibilityGeneration
        guard animated else {
            self.isHiding = false
            self.orderOut(nil)
            return
        }
        self.isHiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, generation == self.visibilityGeneration else {
                return
            }
            self.isHiding = false
            self.orderOut(nil)
        }
    }
}
