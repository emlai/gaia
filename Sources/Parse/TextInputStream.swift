public protocol TextInputStream {
    /// Returns the next character from the stream, or `nil` on EOF.
    func read() -> UnicodeScalar?

    /// Puts the given character (or EOF if `nil`) back to the stream,
    /// to be returned by the next call to `read()`.
    func unread(_ character: UnicodeScalar?)
}

public final class Stdin: TextInputStream {
    private var buffer: String
    private var eof: Bool

    public init() {
        buffer = ""
        eof = false
    }

    public func read() -> UnicodeScalar? {
        if eof { return nil }

        if buffer.isEmpty {
            if let line = readLine(strippingNewline: false) {
                buffer = line
            } else {
                eof = true
                return nil
            }
        }
        return buffer.unicodeScalars.popFirst()
    }

    public func unread(_ character: UnicodeScalar?) {
        if let c = character {
            buffer.unicodeScalars.insert(c, at: buffer.unicodeScalars.startIndex)
        }
        eof = character == nil
    }
}
