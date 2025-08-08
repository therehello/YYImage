import Foundation

public final class DecodeOperation: Operation {
    private let work: () -> Void

    public init(work: @escaping () -> Void) {
        self.work = work
        super.init()
        self.qualityOfService = .userInitiated
    }

    public override func main() {
        if isCancelled { return }
        work()
    }
}