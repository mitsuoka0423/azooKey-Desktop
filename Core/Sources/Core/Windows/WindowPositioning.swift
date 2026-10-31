public enum WindowPositioning {
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Size: Sendable, Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public struct Rect: Sendable, Equatable {
        public var origin: Point
        public var size: Size

        public init(origin: Point, size: Size) {
            self.origin = origin
            self.size = size
        }

        public var minX: Double {
            origin.x
        }
        public var minY: Double {
            origin.y
        }
        public var maxX: Double {
            origin.x + size.width
        }
        public var maxY: Double {
            origin.y + size.height
        }
        public var width: Double {
            size.width
        }
        public var height: Double {
            size.height
        }
    }

    public static func frameNearCursor(
        currentFrame: Rect,
        screenRect: Rect,
        cursorLocation: Point,
        desiredSize: Size,
        cursorHeight: Double = 16
    ) -> Rect {
        var newWindowFrame = currentFrame
        newWindowFrame.size = desiredSize

        let cursorY = cursorLocation.y
        if cursorY - desiredSize.height < screenRect.origin.y {
            newWindowFrame.origin = Point(x: cursorLocation.x, y: cursorLocation.y + cursorHeight)
        } else {
            newWindowFrame.origin = Point(x: cursorLocation.x, y: cursorLocation.y - desiredSize.height - cursorHeight)
        }

        // 横方向のクランプ。まず右端を screenRect 内に収め、
        // ウィンドウが screenRect より広いなど、収まりきらない場合は最終的に minX へ寄せる。
        if newWindowFrame.maxX > screenRect.maxX {
            newWindowFrame.origin.x = screenRect.maxX - newWindowFrame.width
        }
        if newWindowFrame.minX < screenRect.minX {
            newWindowFrame.origin.x = screenRect.minX
        }

        // 縦方向のクランプ。まず上端（maxY）を screenRect 内に収め、
        // ウィンドウが screenRect より高いなど、収まりきらない場合は最終的に minY へ寄せる。
        if newWindowFrame.maxY > screenRect.maxY {
            newWindowFrame.origin.y = screenRect.maxY - newWindowFrame.height
        }
        if newWindowFrame.minY < screenRect.minY {
            newWindowFrame.origin.y = screenRect.minY
        }
        return newWindowFrame
    }

    public static func frameRightOfAnchor(
        currentFrame: Rect,
        anchorFrame: Rect,
        screenRect: Rect,
        gap: Double = 8
    ) -> Rect {
        var frame = currentFrame
        frame.origin.x = anchorFrame.maxX + gap
        frame.origin.y = anchorFrame.origin.y

        if frame.minX < screenRect.minX {
            frame.origin.x = screenRect.minX
        } else if frame.maxX > screenRect.maxX {
            frame.origin.x = screenRect.maxX - frame.width
        }

        if frame.minY < screenRect.minY {
            frame.origin.y = screenRect.minY
        } else if frame.maxY > screenRect.maxY {
            frame.origin.y = screenRect.maxY - frame.height
        }

        return frame
    }

    /// 変換パネルを行の下に出すか上に出すか
    public enum PanelPlacement: Sendable, Equatable {
        case below
        case above
    }

    public struct PanelFrame: Sendable, Equatable {
        public var origin: Point
        public var placement: PanelPlacement

        public init(origin: Point, placement: PanelPlacement) {
            self.origin = origin
            self.placement = placement
        }
    }

    /// 変換パネルの位置を決める。座標は AppKit と同じく左下が原点。
    /// - Parameters:
    ///   - anchor: 変換の始まりの行の矩形（`attributes(forCharacterIndex: 0, lineHeightRectangle:)`）
    ///   - previousPlacement: 同じ変換の中で前回決めた上下。確定するか空になったら `nil` を渡す
    ///   - leftInset: パネルの左端を基準点からどれだけ左に置くか
    public static func liveConversionPanelFrame(
        anchor: Rect,
        panelSize: Size,
        screenRect: Rect,
        previousPlacement: PanelPlacement?,
        leftInset: Double = 12,
        gap: Double = 4
    ) -> PanelFrame {
        var x = anchor.minX - leftInset
        if x + panelSize.width > screenRect.maxX {
            x = screenRect.maxX - panelSize.width
        }
        if x < screenRect.minX {
            x = screenRect.minX
        }

        let belowY = anchor.minY - gap - panelSize.height
        // 一度上に出したら、高さが変わっても下に戻さない
        let placement: PanelPlacement = if previousPlacement == .above || belowY < screenRect.minY {
            .above
        } else {
            .below
        }
        var y = placement == .below ? belowY : anchor.maxY + gap
        // 上にも入りきらないときは画面内に押し込む（仕様の決定事項 5）
        if y + panelSize.height > screenRect.maxY {
            y = screenRect.maxY - panelSize.height
        }
        if y < screenRect.minY {
            y = screenRect.minY
        }
        return PanelFrame(origin: Point(x: x, y: y), placement: placement)
    }

    public static func promptWindowOrigin(
        cursorLocation: Point,
        windowSize: Size,
        screenRect: Rect,
        offsetX: Double = 10,
        belowOffset: Double = 20,
        aboveOffset: Double = 30,
        padding: Double = 20
    ) -> Point {
        var origin = cursorLocation
        origin.x += offsetX
        origin.y -= windowSize.height + belowOffset

        if origin.x + windowSize.width + padding > screenRect.maxX {
            origin.x = screenRect.maxX - windowSize.width - padding
        }

        if origin.x < screenRect.minX + padding {
            origin.x = screenRect.minX + padding
        }

        if origin.y < screenRect.minY + padding {
            origin.y = cursorLocation.y + aboveOffset
            if origin.y + windowSize.height + padding > screenRect.maxY {
                origin.y = screenRect.maxY - windowSize.height - padding
            }
        }

        if origin.y + windowSize.height + padding > screenRect.maxY {
            origin.y = screenRect.maxY - windowSize.height - padding
        }

        return origin
    }
}
