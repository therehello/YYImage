import Foundation

public final class AnimatedImagePlayer: AnimatedImagePlayerType {
    public let id: UUID = UUID()

    public var idealBufferSizeBytes: Int

    private(set) public var maxBufferSizeBytes: Int
    private let bufferAccessQueue = DispatchQueue(label: "player.buffer.access", qos: .userInitiated)

    public init(idealBufferSizeBytes: Int) {
        self.idealBufferSizeBytes = idealBufferSizeBytes
        self.maxBufferSizeBytes = idealBufferSizeBytes
        GlobalAnimatedImageManager.shared.register(player: self)
    }

    deinit {
        GlobalAnimatedImageManager.shared.unregister(player: self)
    }

    public func updateMaxBufferSize(bytes: Int) {
        bufferAccessQueue.async { [weak self] in
            self?.maxBufferSizeBytes = bytes
            // In a real implementation, we would shrink/expand the actual frame buffer here.
        }
    }

    public func requestDecode(task: Operation) {
        GlobalAnimatedImageManager.shared.addDecodeOperation(task)
    }
}