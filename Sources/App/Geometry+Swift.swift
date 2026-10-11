import GnmCocoa

// The bridge's C geometry structs, comparable in Swift.
extension CellCoordinate: @retroactive Equatable {
    public static func == (a: CellCoordinate, b: CellCoordinate) -> Bool {
        a.column == b.column && a.row == b.row
    }
}

extension CellRange: @retroactive Equatable {
    public static func == (a: CellRange, b: CellRange) -> Bool {
        a.start == b.start && a.end == b.end
    }
}
