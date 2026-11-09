//
//  ContentView.swift
//  Carcassonne
//
//  A complete Carcassonne style game for iPhone:
//  72 tiles, roads, cities, monasteries, farmers, meeples, full scoring,
//  computer opponents (Easy, Medium, Hard) and pass and play.
//
//  Paste this over the default ContentView.swift. Needs iOS 17 or newer.
//

import SwiftUI
import Combine
import UIKit

// MARK: - Palette and haptics

enum Palette {
    static let fieldLight = Color(red: 0.58, green: 0.80, blue: 0.38)
    static let fieldDark = Color(red: 0.43, green: 0.68, blue: 0.29)
    static let road = Color(red: 0.97, green: 0.92, blue: 0.78)
    static let roadEdge = Color(red: 0.62, green: 0.50, blue: 0.30)
    static let city = Color(red: 0.84, green: 0.60, blue: 0.31)
    static let cityEdge = Color(red: 0.45, green: 0.26, blue: 0.10)
    static let roof = Color(red: 0.74, green: 0.21, blue: 0.17)
    static let stone = Color(red: 0.93, green: 0.88, blue: 0.78)
    static let shield = Color(red: 0.17, green: 0.36, blue: 0.72)
    static let gold = Color(red: 0.96, green: 0.77, blue: 0.28)
    static let bgTop = Color(red: 0.06, green: 0.21, blue: 0.17)
    static let bgBottom = Color(red: 0.02, green: 0.08, blue: 0.09)
    static let panel = Color(red: 0.07, green: 0.12, blue: 0.11)

    static let playerColors: [Color] = [
        Color(red: 0.88, green: 0.25, blue: 0.22),
        Color(red: 0.19, green: 0.48, blue: 0.91),
        Color(red: 0.97, green: 0.78, blue: 0.19),
        Color(red: 0.17, green: 0.17, blue: 0.20),
        Color(red: 0.58, green: 0.36, blue: 0.84)
    ]

    static func player(_ i: Int) -> Color {
        let n = playerColors.count
        return playerColors[((i % n) + n) % n]
    }
}

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func place() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func score() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// MARK: - Model: geometry and tile definitions
//
// Every tile edge has three "slots", numbered clockwise from the top left:
//   North 0,1,2   East 3,4,5   South 6,7,8   West 9,10,11
// Slot 1, 4, 7 and 10 are the middle of each edge. Every slot belongs to
// exactly one feature (field, road, city). A monastery sits in the centre.

struct Coord: Hashable {
    var x: Int
    var y: Int

    func neighbor(_ side: Int) -> Coord {
        switch side {
        case 0: return Coord(x: x, y: y - 1)
        case 1: return Coord(x: x + 1, y: y)
        case 2: return Coord(x: x, y: y + 1)
        default: return Coord(x: x - 1, y: y)
        }
    }
}

enum FeatureKind {
    case field, road, city, monastery
}

struct Feature {
    let kind: FeatureKind
    let slots: [Int]
    let pos: CGPoint
    let shield: CGPoint?
    var hasShield: Bool { shield != nil }
}

func rotatePoint(_ p: CGPoint, times: Int) -> CGPoint {
    var q = p
    let n = ((times % 4) + 4) % 4
    for _ in 0..<n {
        q = CGPoint(x: 1 - q.y, y: q.x)
    }
    return q
}

struct TileDef {
    let code: String
    let count: Int
    let features: [Feature]
}

private func fld(_ slots: [Int], _ x: Double, _ y: Double) -> Feature {
    Feature(kind: .field, slots: slots, pos: CGPoint(x: x, y: y), shield: nil)
}

private func rod(_ slots: [Int], _ x: Double, _ y: Double) -> Feature {
    Feature(kind: .road, slots: slots, pos: CGPoint(x: x, y: y), shield: nil)
}

private func cty(_ slots: [Int], _ x: Double, _ y: Double, shield: (Double, Double)? = nil) -> Feature {
    var sp: CGPoint? = nil
    if let s = shield { sp = CGPoint(x: s.0, y: s.1) }
    return Feature(kind: .city, slots: slots, pos: CGPoint(x: x, y: y), shield: sp)
}

private func mon(_ x: Double, _ y: Double) -> Feature {
    Feature(kind: .monastery, slots: [], pos: CGPoint(x: x, y: y), shield: nil)
}

enum TileLibrary {
    static let defs: [TileDef] = TileLibrary.makeDefs()
    static let variants: [[PlacedTile]] = TileLibrary.makeVariants()
    static let startIndex: Int = TileLibrary.index("D")

    static func index(_ code: String) -> Int {
        for (i, d) in defs.enumerated() where d.code == code { return i }
        return 0
    }

    private static func makeVariants() -> [[PlacedTile]] {
        var all: [[PlacedTile]] = []
        for i in 0..<TileLibrary.defs.count {
            var row: [PlacedTile] = []
            for r in 0..<4 { row.append(PlacedTile(defIndex: i, rot: r)) }
            all.append(row)
        }
        return all
    }

    private static func makeDefs() -> [TileDef] {
        let all = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        let three = [9, 10, 11, 0, 1, 2, 3, 4, 5]
        let corner = [9, 10, 11, 0, 1, 2]
        let band = [0, 1, 2, 6, 7, 8]
        let cityN = [0, 1, 2]
        var d: [TileDef] = []

        // A: monastery with a road to the south (2)
        d.append(TileDef(code: "A", count: 2, features: [
            mon(0.5, 0.42),
            rod([7], 0.5, 0.88),
            fld([0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11], 0.14, 0.14)
        ]))
        // B: monastery (4)
        d.append(TileDef(code: "B", count: 4, features: [
            mon(0.5, 0.5),
            fld(all, 0.14, 0.14)
        ]))
        // C: full city with shield (1)
        d.append(TileDef(code: "C", count: 1, features: [
            cty(all, 0.5, 0.64, shield: (0.5, 0.3))
        ]))
        // D: city cap with a road across (4, includes the starting tile)
        d.append(TileDef(code: "D", count: 4, features: [
            cty(cityN, 0.5, 0.1),
            rod([4, 10], 0.78, 0.5),
            fld([3, 11], 0.3, 0.37),
            fld([5, 6, 7, 8, 9], 0.5, 0.8)
        ]))
        // E: city cap (5)
        d.append(TileDef(code: "E", count: 5, features: [
            cty(cityN, 0.5, 0.1),
            fld([3, 4, 5, 6, 7, 8, 9, 10, 11], 0.5, 0.7)
        ]))
        // F: city band with shield (2)
        d.append(TileDef(code: "F", count: 2, features: [
            cty(band, 0.5, 0.66, shield: (0.5, 0.3)),
            fld([3, 4, 5], 0.9, 0.5),
            fld([9, 10, 11], 0.1, 0.5)
        ]))
        // G: city band (1)
        d.append(TileDef(code: "G", count: 1, features: [
            cty(band, 0.5, 0.5),
            fld([3, 4, 5], 0.9, 0.5),
            fld([9, 10, 11], 0.1, 0.5)
        ]))
        // H: two separate city caps on opposite sides (3)
        d.append(TileDef(code: "H", count: 3, features: [
            cty(cityN, 0.5, 0.1),
            cty([6, 7, 8], 0.5, 0.9),
            fld([3, 4, 5, 9, 10, 11], 0.5, 0.5)
        ]))
        // I: two separate city caps on adjacent sides (2)
        d.append(TileDef(code: "I", count: 2, features: [
            cty(cityN, 0.5, 0.1),
            cty([3, 4, 5], 0.9, 0.5),
            fld([6, 7, 8, 9, 10, 11], 0.3, 0.7)
        ]))
        // J: city cap with a road curving east to south (3)
        d.append(TileDef(code: "J", count: 3, features: [
            cty(cityN, 0.5, 0.1),
            rod([4, 7], 0.625, 0.625),
            fld([5, 6], 0.88, 0.88),
            fld([8, 9, 10, 11, 3], 0.25, 0.55)
        ]))
        // K: city cap with a road curving south to west (3)
        d.append(TileDef(code: "K", count: 3, features: [
            cty(cityN, 0.5, 0.1),
            rod([7, 10], 0.375, 0.625),
            fld([8, 9], 0.12, 0.88),
            fld([11, 3, 4, 5, 6], 0.75, 0.55)
        ]))
        // L: city cap with a three way crossroad (3)
        d.append(TileDef(code: "L", count: 3, features: [
            cty(cityN, 0.5, 0.1),
            rod([4], 0.82, 0.5),
            rod([7], 0.5, 0.82),
            rod([10], 0.18, 0.5),
            fld([3, 11], 0.5, 0.33),
            fld([5, 6], 0.82, 0.82),
            fld([8, 9], 0.18, 0.82)
        ]))
        // M: corner city with shield (2)
        d.append(TileDef(code: "M", count: 2, features: [
            cty(corner, 0.4, 0.4, shield: (0.2, 0.2)),
            fld([3, 4, 5, 6, 7, 8], 0.7, 0.7)
        ]))
        // N: corner city (3)
        d.append(TileDef(code: "N", count: 3, features: [
            cty(corner, 0.35, 0.35),
            fld([3, 4, 5, 6, 7, 8], 0.7, 0.7)
        ]))
        // O: corner city with shield and a curved road (2)
        d.append(TileDef(code: "O", count: 2, features: [
            cty(corner, 0.36, 0.36, shield: (0.18, 0.18)),
            rod([4, 7], 0.625, 0.625),
            fld([3, 8], 0.8, 0.28),
            fld([5, 6], 0.88, 0.88)
        ]))
        // P: corner city with a curved road (3)
        d.append(TileDef(code: "P", count: 3, features: [
            cty(corner, 0.36, 0.36),
            rod([4, 7], 0.625, 0.625),
            fld([3, 8], 0.8, 0.28),
            fld([5, 6], 0.88, 0.88)
        ]))
        // Q: three sided city with shield (1)
        d.append(TileDef(code: "Q", count: 1, features: [
            cty(three, 0.5, 0.5, shield: (0.5, 0.2)),
            fld([6, 7, 8], 0.5, 0.9)
        ]))
        // R: three sided city (3)
        d.append(TileDef(code: "R", count: 3, features: [
            cty(three, 0.5, 0.5),
            fld([6, 7, 8], 0.5, 0.9)
        ]))
        // S: three sided city with shield and a road (2)
        d.append(TileDef(code: "S", count: 2, features: [
            cty(three, 0.5, 0.45, shield: (0.5, 0.18)),
            rod([7], 0.5, 0.88),
            fld([6], 0.82, 0.9),
            fld([8], 0.18, 0.9)
        ]))
        // T: three sided city with a road (1)
        d.append(TileDef(code: "T", count: 1, features: [
            cty(three, 0.5, 0.45),
            rod([7], 0.5, 0.88),
            fld([6], 0.82, 0.9),
            fld([8], 0.18, 0.9)
        ]))
        // U: straight road (8)
        d.append(TileDef(code: "U", count: 8, features: [
            rod([1, 7], 0.5, 0.5),
            fld([8, 9, 10, 11, 0], 0.2, 0.5),
            fld([2, 3, 4, 5, 6], 0.8, 0.5)
        ]))
        // V: curved road (9)
        d.append(TileDef(code: "V", count: 9, features: [
            rod([7, 10], 0.375, 0.625),
            fld([11, 0, 1, 2, 3, 4, 5, 6], 0.7, 0.3),
            fld([8, 9], 0.12, 0.88)
        ]))
        // W: three way crossroad (4)
        d.append(TileDef(code: "W", count: 4, features: [
            rod([4], 0.82, 0.5),
            rod([7], 0.5, 0.82),
            rod([10], 0.18, 0.5),
            fld([11, 0, 1, 2, 3], 0.5, 0.25),
            fld([5, 6], 0.82, 0.82),
            fld([8, 9], 0.18, 0.82)
        ]))
        // X: four way crossroad (1)
        d.append(TileDef(code: "X", count: 1, features: [
            rod([1], 0.5, 0.18),
            rod([4], 0.82, 0.5),
            rod([7], 0.5, 0.82),
            rod([10], 0.18, 0.5),
            fld([11, 0], 0.18, 0.18),
            fld([2, 3], 0.82, 0.18),
            fld([5, 6], 0.82, 0.82),
            fld([8, 9], 0.18, 0.82)
        ]))
        return d
    }
}

/// A tile with a fixed rotation (0 to 3 quarter turns clockwise).
struct PlacedTile {
    let defIndex: Int
    let rot: Int
    let features: [Feature]
    let slotMap: [Int]
    let fieldCities: [Int: [Int]]

    init(defIndex: Int, rot: Int) {
        let def = TileLibrary.defs[defIndex]
        var feats: [Feature] = []
        for f in def.features {
            var newShield: CGPoint? = nil
            if let sp = f.shield { newShield = rotatePoint(sp, times: rot) }
            feats.append(Feature(
                kind: f.kind,
                slots: f.slots.map { ($0 + 3 * rot) % 12 },
                pos: rotatePoint(f.pos, times: rot),
                shield: newShield))
        }
        var map = [Int](repeating: -1, count: 12)
        for (i, f) in feats.enumerated() {
            for s in f.slots { map[s] = i }
        }
        var fc: [Int: [Int]] = [:]
        for (i, f) in feats.enumerated() where f.kind == .field {
            var cities = Set<Int>()
            for s in f.slots {
                for delta in [-1, 1] {
                    let n = (s + delta + 12) % 12
                    let j = map[n]
                    if j >= 0 && feats[j].kind == .city { cities.insert(j) }
                }
            }
            fc[i] = cities.sorted()
        }
        self.defIndex = defIndex
        self.rot = rot
        self.features = feats
        self.slotMap = map
        self.fieldCities = fc
    }

    func edge(_ side: Int) -> FeatureKind {
        features[slotMap[side * 3 + 1]].kind
    }
}

// MARK: - Model: game state and scoring

struct Node: Hashable, Comparable {
    let c: Coord
    let f: Int

    static func < (a: Node, b: Node) -> Bool {
        if a.c.x != b.c.x { return a.c.x < b.c.x }
        if a.c.y != b.c.y { return a.c.y < b.c.y }
        return a.f < b.f
    }
}

struct PlacedMeeple: Identifiable, Hashable {
    let id = UUID()
    let owner: Int
    let node: Node
}

struct Player: Identifiable {
    let id: Int
    var name: String
    var colorIndex: Int
    var isAI: Bool
    var score: Int = 0
    var meeplesLeft: Int = 7
}

struct ScoreEvent {
    let player: Int
    let points: Int
    let label: String
}

struct Component {
    var kind: FeatureKind
    var nodes: Set<Node>
    var tiles: Set<Coord>
    var shields: Int
    var openEnds: Int
    var isComplete: Bool { openEnds == 0 }
    var key: Node { nodes.min() ?? Node(c: Coord(x: 0, y: 0), f: 0) }
}

private func kindName(_ kind: FeatureKind) -> String {
    switch kind {
    case .city: return "city"
    case .road: return "road"
    case .monastery: return "monastery"
    case .field: return "farm"
    }
}

private func likelihood(_ open: Int) -> Double {
    switch open {
    case ...0: return 1.0
    case 1: return 0.8
    case 2: return 0.6
    case 3: return 0.45
    default: return 0.3
    }
}

struct GameState {
    var board: [Coord: PlacedTile] = [:]
    var meeples: [PlacedMeeple] = []
    var players: [Player] = []
    var deck: [Int] = []
    var current: Int = 0
    var hand: Int? = nil

    // MARK: Placement rules

    func canPlace(_ defIndex: Int, rot: Int, at c: Coord) -> Bool {
        if board[c] != nil { return false }
        let tile = TileLibrary.variants[defIndex][rot]
        var touching = false
        for side in 0..<4 {
            if let nb = board[c.neighbor(side)] {
                touching = true
                if nb.edge((side + 2) % 4) != tile.edge(side) { return false }
            }
        }
        return touching
    }

    func candidateCoords() -> Set<Coord> {
        var set = Set<Coord>()
        for c in board.keys {
            for side in 0..<4 {
                let n = c.neighbor(side)
                if board[n] == nil { set.insert(n) }
            }
        }
        return set
    }

    func hasAnyPlacement(defIndex: Int) -> Bool {
        for c in candidateCoords() {
            for r in 0..<4 where canPlace(defIndex, rot: r, at: c) { return true }
        }
        return false
    }

    func placements(for defIndex: Int) -> [(coord: Coord, rot: Int)] {
        var out: [(coord: Coord, rot: Int)] = []
        for c in candidateCoords() {
            for r in 0..<4 where canPlace(defIndex, rot: r, at: c) {
                out.append((coord: c, rot: r))
            }
        }
        return out
    }

    // MARK: Features and components

    func featureKind(_ n: Node) -> FeatureKind {
        guard let t = board[n.c] else { return .field }
        return t.features[n.f].kind
    }

    func component(from start: Node) -> Component {
        guard let startTile = board[start.c] else {
            return Component(kind: .field, nodes: [], tiles: [], shields: 0, openEnds: 0)
        }
        let kind = startTile.features[start.f].kind
        var visited: Set<Node> = [start]
        var stack: [Node] = [start]
        var open = 0
        var shields = 0
        var tiles = Set<Coord>()
        while let n = stack.popLast() {
            guard let tile = board[n.c] else { continue }
            let feat = tile.features[n.f]
            tiles.insert(n.c)
            if feat.hasShield { shields += 1 }
            for s in feat.slots {
                let side = s / 3
                let k = s % 3
                let nc = n.c.neighbor(side)
                if let nt = board[nc] {
                    let ns = ((side + 2) % 4) * 3 + (2 - k)
                    let nf = nt.slotMap[ns]
                    if nf >= 0 {
                        let nn = Node(c: nc, f: nf)
                        if !visited.contains(nn) {
                            visited.insert(nn)
                            stack.append(nn)
                        }
                    }
                } else if k == 1 && kind != .field {
                    open += 1
                }
            }
        }
        return Component(kind: kind, nodes: visited, tiles: tiles, shields: shields, openEnds: open)
    }

    func meeplesOn(_ comp: Component) -> [PlacedMeeple] {
        meeples.filter { comp.nodes.contains($0.node) }
    }

    func winners(of ms: [PlacedMeeple]) -> [Int] {
        var counts: [Int: Int] = [:]
        for m in ms { counts[m.owner, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        if best == 0 { return [] }
        return counts.filter { $0.value == best }.map { $0.key }.sorted()
    }

    /// Number of tiles in the 3 by 3 block around c, including c itself.
    func surroundCount(_ c: Coord) -> Int {
        var n = 0
        for dx in -1...1 {
            for dy in -1...1 {
                if board[Coord(x: c.x + dx, y: c.y + dy)] != nil { n += 1 }
            }
        }
        return n
    }

    /// Features of the tile at c where a meeple may be placed.
    func eligibleFeatures(at c: Coord) -> [Int] {
        guard let tile = board[c] else { return [] }
        var result: [Int] = []
        for (i, f) in tile.features.enumerated() {
            if f.kind == .monastery {
                result.append(i)
                continue
            }
            let comp = component(from: Node(c: c, f: i))
            if meeplesOn(comp).isEmpty { result.append(i) }
        }
        return result
    }

    func adjacentCities(of comp: Component) -> (done: Set<Node>, open: Set<Node>) {
        var done = Set<Node>()
        var open = Set<Node>()
        var known = Set<Node>()
        for n in comp.nodes {
            guard let t = board[n.c], let cities = t.fieldCities[n.f] else { continue }
            for ci in cities {
                let cn = Node(c: n.c, f: ci)
                if known.contains(cn) { continue }
                let cc = component(from: cn)
                known.formUnion(cc.nodes)
                if cc.isComplete { done.insert(cc.key) } else { open.insert(cc.key) }
            }
        }
        return (done, open)
    }

    func firstMeeple(onField: Bool) -> PlacedMeeple? {
        for m in meeples {
            let isField = featureKind(m.node) == .field
            if isField == onField { return m }
        }
        return nil
    }

    // MARK: Scoring

    /// Scores everything that the tile just placed at c has completed.
    mutating func resolveCompletions(after c: Coord) -> [ScoreEvent] {
        var events: [ScoreEvent] = []
        guard let tile = board[c] else { return events }
        var handled = Set<Node>()
        for (i, f) in tile.features.enumerated() {
            if f.kind != .city && f.kind != .road { continue }
            let comp = component(from: Node(c: c, f: i))
            let key = comp.key
            if handled.contains(key) { continue }
            handled.insert(key)
            if comp.isComplete {
                events += scoreComponent(comp, isFinal: false)
            }
        }
        for dx in -1...1 {
            for dy in -1...1 {
                let cc = Coord(x: c.x + dx, y: c.y + dy)
                guard let t = board[cc] else { continue }
                for (i, f) in t.features.enumerated() where f.kind == .monastery {
                    let node = Node(c: cc, f: i)
                    let hasMeeple = meeples.contains(where: { $0.node == node })
                    if hasMeeple && surroundCount(cc) == 9 {
                        events += scoreMonastery(node, isFinal: false)
                    }
                }
            }
        }
        return events
    }

    private mutating func scoreComponent(_ comp: Component, isFinal: Bool) -> [ScoreEvent] {
        let ms = meeplesOn(comp)
        if ms.isEmpty { return [] }
        let ws = winners(of: ms)
        var pts = 0
        switch comp.kind {
        case .city:
            let units = comp.tiles.count + comp.shields
            pts = isFinal ? units : 2 * units
        case .road:
            pts = comp.tiles.count
        default:
            pts = 0
        }
        let label = (isFinal ? "unfinished " : "completed ") + kindName(comp.kind)
        var events: [ScoreEvent] = []
        for w in ws {
            players[w].score += pts
            events.append(ScoreEvent(player: w, points: pts, label: label))
        }
        for m in ms { players[m.owner].meeplesLeft += 1 }
        let nodes = comp.nodes
        meeples.removeAll(where: { nodes.contains($0.node) })
        return events
    }

    private mutating func scoreMonastery(_ node: Node, isFinal: Bool) -> [ScoreEvent] {
        guard let idx = meeples.firstIndex(where: { $0.node == node }) else { return [] }
        let m = meeples[idx]
        let pts = surroundCount(node.c)
        players[m.owner].score += pts
        players[m.owner].meeplesLeft += 1
        meeples.remove(at: idx)
        let label = (isFinal ? "unfinished " : "completed ") + "monastery"
        return [ScoreEvent(player: m.owner, points: pts, label: label)]
    }

    private mutating func scoreFarm(from node: Node) -> [ScoreEvent] {
        let comp = component(from: node)
        let ms = meeplesOn(comp)
        if ms.isEmpty { return [] }
        let cityCount = adjacentCities(of: comp).done.count
        let pts = 3 * cityCount
        var events: [ScoreEvent] = []
        if pts > 0 {
            for w in winners(of: ms) {
                players[w].score += pts
                events.append(ScoreEvent(player: w, points: pts, label: "farm feeding \(cityCount) cities"))
            }
        }
        for m in ms { players[m.owner].meeplesLeft += 1 }
        let nodes = comp.nodes
        meeples.removeAll(where: { nodes.contains($0.node) })
        return events
    }

    /// End of game scoring for everything still on the board.
    mutating func finalScoring() -> [ScoreEvent] {
        var events: [ScoreEvent] = []
        while let m = firstMeeple(onField: false) {
            if featureKind(m.node) == .monastery {
                events += scoreMonastery(m.node, isFinal: true)
            } else {
                events += scoreComponent(component(from: m.node), isFinal: true)
            }
        }
        while let m = firstMeeple(onField: true) {
            events += scoreFarm(from: m.node)
        }
        return events
    }

    // MARK: Evaluation for the computer player

    /// Expected extra points for each player from meeples that are still on the board.
    func potentials(includeFarms: Bool) -> [Double] {
        var result = [Double](repeating: 0, count: players.count)
        var seen = Set<Node>()
        let progress = 1.0 - Double(deck.count) / 71.0
        for m in meeples {
            let comp = component(from: m.node)
            let key = comp.key
            if seen.contains(key) { continue }
            seen.insert(key)
            var value = 0.0
            switch comp.kind {
            case .city:
                value = Double(2 * (comp.tiles.count + comp.shields)) * likelihood(comp.openEnds)
            case .road:
                value = Double(comp.tiles.count) * likelihood(comp.openEnds)
            case .monastery:
                let n = surroundCount(m.node.c)
                value = Double(n) + 0.35 * Double(9 - n)
            case .field:
                if includeFarms {
                    let adj = adjacentCities(of: comp)
                    value = (2.5 * Double(adj.done.count) + 0.8 * Double(adj.open.count)) * (0.5 + progress)
                }
            }
            for w in winners(of: meeplesOn(comp)) { result[w] += value }
        }
        return result
    }
}

// MARK: - Computer player

enum Difficulty: String, CaseIterable, Identifiable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    var id: String { rawValue }
}

struct AIMove {
    let coord: Coord
    let rot: Int
    let feature: Int?
}

enum AIBrain {
    static func chooseMove(state: GameState, defIndex: Int, me: Int, difficulty: Difficulty) -> AIMove? {
        var options: [AIMove] = []
        let canMeeple = state.players[me].meeplesLeft > 0
        for place in state.placements(for: defIndex) {
            options.append(AIMove(coord: place.coord, rot: place.rot, feature: nil))
            if canMeeple {
                var s = state
                s.board[place.coord] = TileLibrary.variants[defIndex][place.rot]
                for f in s.eligibleFeatures(at: place.coord) {
                    options.append(AIMove(coord: place.coord, rot: place.rot, feature: f))
                }
            }
        }
        if options.isEmpty { return nil }
        if difficulty == .easy {
            options = Array(options.shuffled().prefix(6))
        }
        var best = options[0]
        var bestValue = -Double.infinity
        for mv in options {
            var v = value(of: mv, in: state, defIndex: defIndex, me: me, difficulty: difficulty)
            if difficulty == .medium { v += Double.random(in: -1.2...1.2) }
            if difficulty == .easy { v += Double.random(in: -2.0...2.0) }
            if v > bestValue {
                bestValue = v
                best = mv
            }
        }
        return best
    }

    private static func value(of mv: AIMove, in state: GameState, defIndex: Int, me: Int, difficulty: Difficulty) -> Double {
        var s = state
        s.board[mv.coord] = TileLibrary.variants[defIndex][mv.rot]
        if let f = mv.feature {
            s.meeples.append(PlacedMeeple(owner: me, node: Node(c: mv.coord, f: f)))
            s.players[me].meeplesLeft -= 1
        }
        _ = s.resolveCompletions(after: mv.coord)

        var v = Double(s.players[me].score - state.players[me].score)
        for q in s.players.indices where q != me {
            v -= 0.7 * Double(s.players[q].score - state.players[q].score)
        }
        if difficulty == .easy { return v }

        let weight = difficulty == .hard ? 1.0 : 0.6
        let pot = s.potentials(includeFarms: difficulty == .hard)
        var others = 0.0
        for q in pot.indices where q != me { others += pot[q] }
        v += weight * (pot[me] - 0.7 * others)

        if mv.feature != nil && s.players[me].meeplesLeft == state.players[me].meeplesLeft - 1 {
            let left = state.players[me].meeplesLeft
            v -= left <= 2 ? 3.0 : (left <= 4 ? 1.6 : 0.8)
        }
        return v
    }
}

// MARK: - Game engine

@MainActor
final class GameEngine: ObservableObject {
    enum Phase {
        case placeTile, placeMeeple, gameOver
    }

    @Published var state: GameState
    @Published var phase: Phase = .placeTile
    @Published var spin: Int = 0
    @Published var lastPlaced: Coord? = nil
    @Published var banner: String? = nil

    let difficulty: Difficulty
    private var turnToken = 0
    private var bannerToken = 0

    var rotation: Int { ((spin % 4) + 4) % 4 }
    var currentPlayer: Player { state.players[state.current] }
    var isAITurn: Bool { phase != .gameOver && currentPlayer.isAI }
    var tilesLeft: Int { state.deck.count + (state.hand == nil ? 0 : 1) }

    var legalSpots: [Coord] {
        guard phase == .placeTile, !isAITurn, let h = state.hand else { return [] }
        return Array(state.candidateCoords().filter { state.canPlace(h, rot: rotation, at: $0) })
    }

    var meepleOptions: [Int] {
        guard let c = lastPlaced else { return [] }
        return state.eligibleFeatures(at: c)
    }

    init(players: [Player], difficulty: Difficulty) {
        self.difficulty = difficulty
        var s = GameState()
        s.players = players
        var deck: [Int] = []
        for (i, d) in TileLibrary.defs.enumerated() {
            let n = (i == TileLibrary.startIndex) ? d.count - 1 : d.count
            deck += Array(repeating: i, count: n)
        }
        deck.shuffle()
        s.deck = deck
        s.board[Coord(x: 0, y: 0)] = TileLibrary.variants[TileLibrary.startIndex][0]
        self.state = s
        drawTile()
        beginTurn()
    }

    // MARK: Turn flow

    private func drawTile() {
        state.hand = nil
        while let next = state.deck.popLast() {
            if state.hasAnyPlacement(defIndex: next) {
                state.hand = next
                spin = firstValidRotation(for: next)
                phase = .placeTile
                return
            }
        }
        finishGame()
    }

    private func firstValidRotation(for def: Int) -> Int {
        let coords = state.candidateCoords()
        for r in 0..<4 {
            for c in coords where state.canPlace(def, rot: r, at: c) { return r }
        }
        return 0
    }

    private func finishGame() {
        let events = state.finalScoring()
        report(events, isFinal: true)
        state.hand = nil
        phase = .gameOver
        Haptics.score()
    }

    func rotate() {
        guard phase == .placeTile, !isAITurn, let h = state.hand else { return }
        let coords = state.candidateCoords()
        for step in 1...4 {
            let r = (rotation + step) % 4
            if coords.contains(where: { state.canPlace(h, rot: r, at: $0) }) {
                spin += step
                Haptics.tap()
                return
            }
        }
    }

    func placeTile(at c: Coord) {
        guard phase == .placeTile, !isAITurn, let h = state.hand,
              state.canPlace(h, rot: rotation, at: c) else { return }
        state.board[c] = TileLibrary.variants[h][rotation]
        lastPlaced = c
        phase = .placeMeeple
        Haptics.place()
        let me = state.current
        if state.players[me].meeplesLeft == 0 || state.eligibleFeatures(at: c).isEmpty {
            commitTurn(meeple: nil)
        }
    }

    func undoTile() {
        guard phase == .placeMeeple, !isAITurn, let c = lastPlaced else { return }
        state.board[c] = nil
        lastPlaced = nil
        phase = .placeTile
        Haptics.tap()
    }

    func commitTurn(meeple feature: Int?) {
        guard phase == .placeMeeple, let c = lastPlaced else { return }
        let me = state.current
        if let f = feature {
            state.meeples.append(PlacedMeeple(owner: me, node: Node(c: c, f: f)))
            state.players[me].meeplesLeft -= 1
            Haptics.tap()
        }
        let events = state.resolveCompletions(after: c)
        report(events, isFinal: false)
        state.hand = nil
        state.current = (state.current + 1) % state.players.count
        drawTile()
        if phase != .gameOver { beginTurn() }
    }

    // MARK: Computer turns

    private func beginTurn() {
        guard phase == .placeTile, isAITurn else { return }
        turnToken += 1
        let token = turnToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self = self, self.turnToken == token else { return }
            self.runAI()
        }
    }

    private func runAI() {
        guard phase == .placeTile, isAITurn, let h = state.hand else { return }
        let me = state.current
        guard let mv = AIBrain.chooseMove(state: state, defIndex: h, me: me, difficulty: difficulty) else {
            state.hand = nil
            drawTile()
            if phase != .gameOver { beginTurn() }
            return
        }
        spin = mv.rot
        state.board[mv.coord] = TileLibrary.variants[h][mv.rot]
        lastPlaced = mv.coord
        phase = .placeMeeple
        Haptics.place()
        turnToken += 1
        let token = turnToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self = self, self.turnToken == token else { return }
            self.commitTurn(meeple: mv.feature)
        }
    }

    // MARK: Messages

    private func report(_ events: [ScoreEvent], isFinal: Bool) {
        if events.isEmpty { return }
        var lines: [String] = []
        for e in events {
            lines.append("\(state.players[e.player].name)  +\(e.points)  \(e.label)")
        }
        if !isFinal { showBanner(lines.prefix(4).joined(separator: "\n")) }
        Haptics.score()
    }

    private func showBanner(_ text: String) {
        bannerToken += 1
        let token = bannerToken
        banner = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard let self = self, self.bannerToken == token else { return }
            self.banner = nil
        }
    }
}

// MARK: - Drawing: meeples

struct MeepleBody: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(Double, Double)] = [
            (0.58, 0.30), (0.78, 0.34), (0.96, 0.46), (0.99, 0.56), (0.88, 0.62),
            (0.72, 0.55), (0.68, 0.66), (0.80, 0.82), (0.94, 0.99), (0.60, 0.99),
            (0.50, 0.84), (0.40, 0.99), (0.06, 0.99), (0.20, 0.82), (0.32, 0.66),
            (0.28, 0.55), (0.12, 0.62), (0.01, 0.56), (0.04, 0.46), (0.22, 0.34),
            (0.42, 0.30)
        ]
        var p = Path()
        for (i, q) in pts.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat(q.0) * rect.width,
                                y: rect.minY + CGFloat(q.1) * rect.height)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

struct MeepleHead: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: rect.minX + 0.34 * rect.width,
                               y: rect.minY + 0.0 * rect.height,
                               width: 0.32 * rect.width,
                               height: 0.32 * rect.height))
    }
}

struct MeepleView: View {
    var color: Color
    var size: CGFloat
    var lying: Bool = false
    var outline: Color = Color.black.opacity(0.55)

    var body: some View {
        let lw = max(1, size * 0.09)
        ZStack {
            MeepleBody().stroke(outline, style: StrokeStyle(lineWidth: lw, lineJoin: .round))
            MeepleHead().stroke(outline, style: StrokeStyle(lineWidth: lw, lineJoin: .round))
            MeepleBody().fill(color)
            MeepleHead().fill(color)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(lying ? 90 : 0))
        .shadow(color: Color.black.opacity(0.35), radius: size * 0.05, x: 0, y: size * 0.04)
    }
}

// MARK: - Drawing: tiles

enum TileArt {
    static func edgeMid(_ side: Int) -> CGPoint {
        switch side {
        case 0: return CGPoint(x: 0.5, y: 0.0)
        case 1: return CGPoint(x: 1.0, y: 0.5)
        case 2: return CGPoint(x: 0.5, y: 1.0)
        default: return CGPoint(x: 0.0, y: 0.5)
        }
    }

    static func scaled(_ p: CGPoint, _ s: CGFloat) -> CGPoint {
        CGPoint(x: p.x * s, y: p.y * s)
    }

    static func draw(_ ctx: inout GraphicsContext, def: TileDef, size: CGSize) {
        let s = min(size.width, size.height)
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        ctx.clip(to: Path(rect))

        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Palette.fieldLight, Palette.fieldDark]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: s, y: s)))
        drawTufts(&ctx, s: s)

        let roads = def.features.filter { $0.kind == .road }
        let hasMonastery = def.features.contains(where: { $0.kind == .monastery })
        let hasRoad = !roads.isEmpty

        for f in roads {
            drawRoad(&ctx, feature: f, s: s, roadCount: roads.count, hasMonastery: hasMonastery)
        }
        if roads.count >= 3 {
            let r = s * 0.07
            ctx.fill(Path(ellipseIn: CGRect(x: s / 2 - r, y: s / 2 - r, width: r * 2, height: r * 2)),
                     with: .color(Palette.roadEdge))
        }
        for f in def.features where f.kind == .city {
            drawCity(&ctx, feature: f, s: s, hasRoad: hasRoad)
        }
        if hasMonastery { drawMonastery(&ctx, s: s) }
        for f in def.features where f.kind == .city {
            if let sp = f.shield { drawShield(&ctx, at: sp, s: s) }
        }
        ctx.stroke(Path(rect), with: .color(Color.black.opacity(0.28)), lineWidth: 1)
    }

    private static func drawTufts(_ ctx: inout GraphicsContext, s: CGFloat) {
        let pts: [(Double, Double)] = [
            (0.12, 0.2), (0.82, 0.12), (0.9, 0.78), (0.2, 0.88),
            (0.55, 0.64), (0.38, 0.3), (0.7, 0.45)
        ]
        for p in pts {
            let r = CGRect(x: CGFloat(p.0) * s - s * 0.035, y: CGFloat(p.1) * s - s * 0.02,
                           width: s * 0.07, height: s * 0.04)
            ctx.fill(Path(ellipseIn: r), with: .color(Color.black.opacity(0.06)))
        }
    }

    private static func drawRoad(_ ctx: inout GraphicsContext, feature f: Feature, s: CGFloat,
                                 roadCount: Int, hasMonastery: Bool) {
        var p = Path()
        let ends = f.slots.map { edgeMid($0 / 3) }
        if ends.count >= 2 {
            p.move(to: scaled(ends[0], s))
            p.addQuadCurve(to: scaled(ends[1], s), control: CGPoint(x: s / 2, y: s / 2))
        } else if let e = ends.first {
            let t: CGFloat = roadCount >= 3 ? 1.0 : (hasMonastery ? 0.78 : 0.62)
            let inner = CGPoint(x: e.x + (0.5 - e.x) * t, y: e.y + (0.5 - e.y) * t)
            p.move(to: scaled(e, s))
            p.addLine(to: scaled(inner, s))
        }
        ctx.stroke(p, with: .color(Palette.roadEdge),
                   style: StrokeStyle(lineWidth: s * 0.17, lineCap: .butt, lineJoin: .round))
        ctx.stroke(p, with: .color(Palette.road),
                   style: StrokeStyle(lineWidth: s * 0.115, lineCap: .butt, lineJoin: .round))
    }

    private static func cityShape(sides: Set<Int>, hasRoad: Bool) -> (fill: Path, border: Path) {
        var fill = Path()
        var border = Path()
        var turns = 0
        let count = sides.count
        if count == 1 {
            fill.move(to: CGPoint(x: 0, y: 0))
            fill.addLine(to: CGPoint(x: 1, y: 0))
            fill.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: 0.5, y: 0.58))
            fill.closeSubpath()
            border.move(to: CGPoint(x: 1, y: 0))
            border.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: 0.5, y: 0.58))
            turns = sides.first ?? 0
        } else if count == 2 {
            let opposite = (sides.contains(0) && sides.contains(2)) || (sides.contains(1) && sides.contains(3))
            if opposite {
                fill.move(to: CGPoint(x: 0, y: 0))
                fill.addLine(to: CGPoint(x: 1, y: 0))
                fill.addQuadCurve(to: CGPoint(x: 1, y: 1), control: CGPoint(x: 0.62, y: 0.5))
                fill.addLine(to: CGPoint(x: 0, y: 1))
                fill.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: 0.38, y: 0.5))
                fill.closeSubpath()
                border.move(to: CGPoint(x: 1, y: 0))
                border.addQuadCurve(to: CGPoint(x: 1, y: 1), control: CGPoint(x: 0.62, y: 0.5))
                border.move(to: CGPoint(x: 0, y: 1))
                border.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: 0.38, y: 0.5))
                turns = sides.contains(0) ? 0 : 1
            } else {
                let b: CGFloat = hasRoad ? 0.0 : 0.2
                let control = CGPoint(x: 0.5 - b, y: 0.5 + b)
                fill.move(to: CGPoint(x: 0, y: 0))
                fill.addLine(to: CGPoint(x: 1, y: 0))
                fill.addLine(to: CGPoint(x: 1, y: 1))
                fill.addQuadCurve(to: CGPoint(x: 0, y: 0), control: control)
                fill.closeSubpath()
                border.move(to: CGPoint(x: 1, y: 1))
                border.addQuadCurve(to: CGPoint(x: 0, y: 0), control: control)
                var a = 0
                for k in 0..<4 where sides.contains(k) && sides.contains((k + 1) % 4) { a = k }
                turns = a
            }
        } else if count == 3 {
            fill.move(to: CGPoint(x: 0, y: 0))
            fill.addLine(to: CGPoint(x: 1, y: 0))
            fill.addLine(to: CGPoint(x: 1, y: 1))
            fill.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 0.5, y: 0.45))
            fill.closeSubpath()
            border.move(to: CGPoint(x: 1, y: 1))
            border.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 0.5, y: 0.45))
            var missing = 2
            for k in 0..<4 where !sides.contains(k) { missing = k }
            turns = (missing + 2) % 4
        } else {
            fill.addRect(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        if turns > 0 {
            let t = CGAffineTransform(translationX: 0.5, y: 0.5)
                .rotated(by: CGFloat(turns) * CGFloat.pi / 2)
                .translatedBy(x: -0.5, y: -0.5)
            fill = fill.applying(t)
            border = border.applying(t)
        }
        return (fill, border)
    }

    private static func drawCity(_ ctx: inout GraphicsContext, feature f: Feature, s: CGFloat, hasRoad: Bool) {
        let sides = Set(f.slots.map { $0 / 3 })
        let shape = cityShape(sides: sides, hasRoad: hasRoad)
        let t = CGAffineTransform(scaleX: s, y: s)
        let fill = shape.fill.applying(t)
        let border = shape.border.applying(t)
        ctx.fill(fill, with: .color(Palette.city))

        var inner = ctx
        inner.clip(to: fill)
        let step = s / 8
        for i in 1..<8 {
            let v = CGFloat(i) * step
            var h = Path()
            h.move(to: CGPoint(x: 0, y: v))
            h.addLine(to: CGPoint(x: s, y: v))
            var w = Path()
            w.move(to: CGPoint(x: v, y: 0))
            w.addLine(to: CGPoint(x: v, y: s))
            inner.stroke(h, with: .color(Color.black.opacity(0.09)), lineWidth: 1)
            inner.stroke(w, with: .color(Color.black.opacity(0.09)), lineWidth: 1)
        }
        ctx.stroke(border, with: .color(Palette.cityEdge),
                   style: StrokeStyle(lineWidth: s * 0.045, lineCap: .butt, lineJoin: .round))
    }

    private static func drawShield(_ ctx: inout GraphicsContext, at p: CGPoint, s: CGFloat) {
        let w = s * 0.2
        let cx = p.x * s
        let cy = p.y * s
        var path = Path()
        path.move(to: CGPoint(x: cx - w / 2, y: cy - w * 0.55))
        path.addLine(to: CGPoint(x: cx + w / 2, y: cy - w * 0.55))
        path.addLine(to: CGPoint(x: cx + w / 2, y: cy + w * 0.1))
        path.addQuadCurve(to: CGPoint(x: cx, y: cy + w * 0.7), control: CGPoint(x: cx + w / 2, y: cy + w * 0.5))
        path.addQuadCurve(to: CGPoint(x: cx - w / 2, y: cy + w * 0.1), control: CGPoint(x: cx - w / 2, y: cy + w * 0.5))
        path.closeSubpath()
        ctx.fill(path, with: .color(Palette.shield))
        ctx.stroke(path, with: .color(Palette.gold), style: StrokeStyle(lineWidth: max(1, s * 0.022), lineJoin: .round))
        let bar = Path(CGRect(x: cx - w * 0.28, y: cy - w * 0.2, width: w * 0.56, height: w * 0.16))
        ctx.fill(bar, with: .color(Palette.gold))
    }

    private static func drawMonastery(_ ctx: inout GraphicsContext, s: CGFloat) {
        func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(w) * s, height: CGFloat(h) * s)
        }
        let lw = max(1, s * 0.014)
        ctx.fill(Path(ellipseIn: r(0.24, 0.62, 0.52, 0.12)), with: .color(Color.black.opacity(0.18)))
        ctx.fill(Path(r(0.33, 0.44, 0.34, 0.24)), with: .color(Palette.stone))
        ctx.stroke(Path(r(0.33, 0.44, 0.34, 0.24)), with: .color(Palette.cityEdge), lineWidth: lw)
        var roof = Path()
        roof.move(to: CGPoint(x: 0.27 * s, y: 0.45 * s))
        roof.addLine(to: CGPoint(x: 0.50 * s, y: 0.22 * s))
        roof.addLine(to: CGPoint(x: 0.73 * s, y: 0.45 * s))
        roof.closeSubpath()
        ctx.fill(roof, with: .color(Palette.roof))
        ctx.stroke(roof, with: .color(Palette.cityEdge), lineWidth: lw)
        ctx.fill(Path(roundedRect: r(0.455, 0.54, 0.09, 0.14), cornerRadius: s * 0.03), with: .color(Palette.cityEdge))
        ctx.fill(Path(r(0.488, 0.09, 0.024, 0.13)), with: .color(Color.white))
        ctx.fill(Path(r(0.46, 0.125, 0.08, 0.024)), with: .color(Color.white))
    }
}

struct TileView: View {
    let defIndex: Int
    var rot: Int = 0

    var body: some View {
        let def = TileLibrary.defs[defIndex]
        Canvas { context, size in
            var ctx = context
            TileArt.draw(&ctx, def: def, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .rotationEffect(.degrees(Double(rot) * 90))
    }
}

// MARK: - Root view

struct ContentView: View {
    @State private var engine: GameEngine? = nil
    @State private var setup: [Player] = []
    @State private var setupDifficulty: Difficulty = .medium

    var body: some View {
        ZStack {
            if let engine = engine {
                GameView(engine: engine,
                         onRestart: { startGame(setup, setupDifficulty) },
                         onQuit: { self.engine = nil })
            } else {
                MenuView(onStart: { players, diff in startGame(players, diff) })
            }
        }
        .preferredColorScheme(.dark)
    }

    private func startGame(_ players: [Player], _ diff: Difficulty) {
        setup = players
        setupDifficulty = diff
        engine = GameEngine(players: players, difficulty: diff)
    }
}

// MARK: - Menu

struct MenuView: View {
    var onStart: ([Player], Difficulty) -> Void

    @State private var count = 2
    @State private var names = ["You", "Aria", "Leo", "Mia", "Sam"]
    @State private var cpu = [false, true, true, true, true]
    @State private var difficulty: Difficulty = .medium
    @State private var showRules = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    logo
                    presets
                    playersCard
                    if cpu.prefix(count).contains(true) { difficultyCard }
                    startButton
                    Button("How to play") { showRules = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.gold)
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showRules) { RulesView() }
    }

    private var logo: some View {
        VStack(spacing: 12) {
            HStack(spacing: -8) {
                logoTile("O", rot: 0, angle: -9)
                logoTile("J", rot: 1, angle: 4)
                logoTile("M", rot: 2, angle: -3)
                logoTile("A", rot: 0, angle: 8)
            }
            .padding(.top, 20)
            Text("CARCASSONNE")
                .font(.system(size: 36, weight: .black, design: .serif))
                .tracking(2)
                .foregroundStyle(Palette.gold)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            Text("Build the map. Claim the land.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    private func logoTile(_ code: String, rot: Int, angle: Double) -> some View {
        TileView(defIndex: TileLibrary.index(code), rot: rot)
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.6), lineWidth: 1))
            .rotationEffect(.degrees(angle))
            .shadow(color: Color.black.opacity(0.5), radius: 6, x: 0, y: 4)
    }

    private var presets: some View {
        HStack(spacing: 10) {
            presetButton("Solo vs CPU", "person.fill") {
                count = 2
                cpu = [false, true, true, true, true]
            }
            presetButton("Pass and play", "person.2.fill") {
                count = 2
                cpu = [false, false, false, false, false]
            }
            presetButton("Full table", "person.3.fill") {
                count = 4
                cpu = [false, true, true, true, true]
            }
        }
    }

    private func presetButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var playersCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Players").font(.headline)
                Spacer()
                Text("\(count)").font(.headline).foregroundStyle(Palette.gold)
                Stepper("Players", value: $count, in: 2...5).labelsHidden()
            }
            ForEach(0..<count, id: \.self) { i in
                playerRow(i)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }

    private func playerRow(_ i: Int) -> some View {
        HStack(spacing: 10) {
            MeepleView(color: Palette.player(i), size: 30, outline: Color.white.opacity(0.8))
            TextField("Name", text: $names[i])
                .padding(9)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            Toggle(isOn: $cpu[i]) {
                Text("CPU").font(.caption.weight(.bold))
            }
            .tint(Palette.gold)
            .fixedSize()
        }
    }

    private var difficultyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Computer skill").font(.headline)
            Picker("Difficulty", selection: $difficulty) {
                ForEach(Difficulty.allCases) { d in
                    Text(d.rawValue).tag(d)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }

    private var startButton: some View {
        Button {
            start()
        } label: {
            Text("Start game")
                .font(.title3.weight(.heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Palette.gold, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(Color.black)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func start() {
        var list: [Player] = []
        for i in 0..<count {
            let trimmed = names[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? "Player \(i + 1)" : trimmed
            list.append(Player(id: i, name: name, colorIndex: i, isAI: cpu[i]))
        }
        onStart(list, difficulty)
    }
}

// MARK: - Rules

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rule("Your turn",
                         "Draw a tile and place it next to the tiles already on the table. Every touching edge must match: road to road, city to city, field to field. Tap the Rotate button to turn the tile, then tap a glowing spot.")
                    rule("Meeples",
                         "After placing a tile you may place one meeple on it. Each player has 7. Put it on a city (knight), a road (thief), a monastery (monk) or a field (farmer, lying down). You cannot place a meeple on a city, road or field that already has a meeple, even if it is connected through other tiles.")
                    rule("Cities",
                         "A finished city scores 2 points per tile plus 2 points per shield. An unfinished city scores 1 point per tile and shield at the end of the game.")
                    rule("Roads",
                         "A finished road scores 1 point per tile. An unfinished road scores the same at the end of the game.")
                    rule("Monasteries",
                         "A monastery surrounded by 8 tiles scores 9 points. If unfinished at the end it scores 1 point for itself and 1 for each tile around it.")
                    rule("Farmers",
                         "Farmers stay in their field until the end of the game. Then each completed city touching the field is worth 3 points to the player with the most farmers there.")
                    rule("Sharing",
                         "When a feature finishes, the player with the most meeples on it scores. If there is a tie, everyone tied scores in full. Meeples on finished cities, roads and monasteries go back to their owners.")
                    rule("Game end",
                         "The game ends when the last tile is placed. Tiles that fit nowhere are discarded. The highest score wins.")
                }
                .padding(20)
            }
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rule(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Palette.gold)
            Text(text).font(.subheadline)
        }
    }
}

// MARK: - Game screen

struct GameView: View {
    @ObservedObject var engine: GameEngine
    var onRestart: () -> Void
    var onQuit: () -> Void

    @State private var showRules = false
    @State private var showMenu = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScoreStrip(engine: engine)
                BoardView(engine: engine)
                    .overlay(alignment: .top) { bannerView }
                BottomPanel(engine: engine)
            }
            if engine.phase == .gameOver {
                GameOverView(engine: engine, onAgain: onRestart, onQuit: onQuit)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showRules) { RulesView() }
        .confirmationDialog("Game menu", isPresented: $showMenu, titleVisibility: .visible) {
            Button("How to play") { showRules = true }
            Button("Restart game", role: .destructive) { onRestart() }
            Button("Quit to main menu", role: .destructive) { onQuit() }
            Button("Cancel", role: .cancel) {}
        }
        .animation(.easeInOut(duration: 0.3), value: engine.phase)
    }

    private var topBar: some View {
        HStack {
            Button { showMenu = true } label: {
                Image(systemName: "line.3.horizontal.circle.fill").font(.title2)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("CARCASSONNE")
                    .font(.system(size: 15, weight: .black, design: .serif))
                    .tracking(2)
                    .foregroundStyle(Palette.gold)
                Text("\(engine.tilesLeft) tiles left")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Spacer()
            Button { showRules = true } label: {
                Image(systemName: "questionmark.circle.fill").font(.title2)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var bannerView: some View {
        Group {
            if let b = engine.banner {
                Text(b)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold, lineWidth: 1))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: engine.banner)
    }
}

struct ScoreStrip: View {
    @ObservedObject var engine: GameEngine

    var body: some View {
        HStack(spacing: 6) {
            ForEach(engine.state.players) { p in
                PlayerChip(player: p, active: p.id == engine.state.current && engine.phase != .gameOver)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct PlayerChip: View {
    let player: Player
    let active: Bool

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                MeepleView(color: Palette.player(player.colorIndex), size: 14, outline: Color.white.opacity(0.85))
                Text(player.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text("\(player.score)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Text("\(player.meeplesLeft) meeples")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(active ? 0.2 : 0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Palette.gold : Color.clear, lineWidth: 2))
        .foregroundStyle(.white)
    }
}

// MARK: - Board

struct BoardView: View {
    @ObservedObject var engine: GameEngine

    private let tile: CGFloat = 86
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var pulse = false
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let liveScale = min(max(scale * pinch, 0.3), 2.8)
            let liveOffset = CGSize(width: offset.width + dragDelta.width,
                                    height: offset.height + dragDelta.height)
            ZStack {
                Color.clear.contentShape(Rectangle())
                world
                    .scaleEffect(liveScale)
                    .offset(liveOffset)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .overlay(alignment: .bottomTrailing) { controls }
            .onChange(of: engine.lastPlaced) { _, newValue in
                follow(newValue, size: geo.size)
            }
        }
        .onAppear { pulse = true }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragDelta) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset = CGSize(width: offset.width + value.translation.width,
                                height: offset.height + value.translation.height)
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                scale = min(max(scale * value.magnification, 0.3), 2.8)
            }
    }

    private func follow(_ coord: Coord?, size: CGSize) {
        guard let c = coord else { return }
        let px = CGFloat(c.x) * tile * scale + offset.width
        let py = CGFloat(c.y) * tile * scale + offset.height
        let limitX = size.width / 2 - tile * scale * 0.8
        let limitY = size.height / 2 - tile * scale * 0.8
        if abs(px) > limitX || abs(py) > limitY {
            withAnimation(.easeInOut(duration: 0.5)) {
                offset = CGSize(width: -CGFloat(c.x) * tile * scale, height: -CGFloat(c.y) * tile * scale)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            controlButton("plus") { withAnimation { scale = min(scale * 1.25, 2.8) } }
            controlButton("minus") { withAnimation { scale = max(scale / 1.25, 0.3) } }
            controlButton("scope") {
                withAnimation {
                    scale = 1.0
                    offset = .zero
                }
            }
        }
        .padding(10)
    }

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var world: some View {
        let spots = engine.legalSpots
        return ZStack {
            ForEach(Array(engine.state.board.keys), id: \.self) { c in
                if let t = engine.state.board[c] {
                    TileView(defIndex: t.defIndex, rot: t.rot)
                        .frame(width: tile, height: tile)
                        .offset(x: CGFloat(c.x) * tile, y: CGFloat(c.y) * tile)
                }
            }
            if let lp = engine.lastPlaced, engine.state.board[lp] != nil {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Palette.gold, lineWidth: 3)
                    .frame(width: tile, height: tile)
                    .offset(x: CGFloat(lp.x) * tile, y: CGFloat(lp.y) * tile)
                    .allowsHitTesting(false)
            }
            ForEach(spots, id: \.self) { c in
                spotView(c)
            }
            ForEach(engine.state.meeples) { m in
                meepleView(m)
            }
        }
    }

    private func spotView(_ c: Coord) -> some View {
        Button {
            engine.placeTile(at: c)
        } label: {
            ZStack {
                if let h = engine.state.hand {
                    TileView(defIndex: h, rot: engine.rotation)
                        .opacity(pulse ? 0.55 : 0.25)
                }
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .frame(width: tile - 2, height: tile - 2)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .offset(x: CGFloat(c.x) * tile, y: CGFloat(c.y) * tile)
    }

    private func meepleView(_ m: PlacedMeeple) -> some View {
        let t = engine.state.board[m.node.c]
        let feat = t?.features[m.node.f]
        let p = feat?.pos ?? CGPoint(x: 0.5, y: 0.5)
        let farmer = feat?.kind == .field
        let colorIndex = engine.state.players[m.owner].colorIndex
        return MeepleView(color: Palette.player(colorIndex), size: tile * 0.4, lying: farmer)
            .offset(x: CGFloat(m.node.c.x) * tile + (p.x - 0.5) * tile,
                    y: CGFloat(m.node.c.y) * tile + (p.y - 0.5) * tile)
            .allowsHitTesting(false)
    }
}

// MARK: - Bottom panel

struct BottomPanel: View {
    @ObservedObject var engine: GameEngine

    var body: some View {
        VStack(spacing: 0) {
            if engine.phase == .gameOver {
                EmptyView()
            } else if engine.isAITurn {
                TurnTray(engine: engine)
            } else if engine.phase == .placeMeeple {
                MeeplePicker(engine: engine)
            } else {
                TurnTray(engine: engine)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Palette.panel.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }
}

struct TurnTray: View {
    @ObservedObject var engine: GameEngine

    private var statusLine: String {
        if engine.isAITurn { return "\(engine.tilesLeft) tiles left" }
        if engine.legalSpots.isEmpty { return "Rotate the tile to find a spot" }
        return "Tap a glowing spot. \(engine.tilesLeft) tiles left"
    }

    var body: some View {
        let player = engine.currentPlayer
        HStack(spacing: 14) {
            if let h = engine.state.hand {
                TileView(defIndex: h, rot: engine.spin)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.gold, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.5), radius: 5, x: 0, y: 3)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: engine.spin)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    MeepleView(color: Palette.player(player.colorIndex), size: 18, outline: Color.white.opacity(0.85))
                    Text(engine.isAITurn ? "\(player.name) is thinking" : "\(player.name), your turn")
                        .font(.headline)
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            if engine.isAITurn {
                ProgressView().tint(.white)
            } else {
                Button {
                    engine.rotate()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 22, weight: .bold))
                        Text("Rotate").font(.caption2.weight(.semibold))
                    }
                    .frame(width: 66, height: 66)
                    .background(Palette.gold, in: Circle())
                    .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct MeeplePicker: View {
    @ObservedObject var engine: GameEngine
    private let side: CGFloat = 196

    var body: some View {
        if let c = engine.lastPlaced, let t = engine.state.board[c] {
            let color = Palette.player(engine.currentPlayer.colorIndex)
            VStack(spacing: 8) {
                HStack {
                    Text("Place a meeple?").font(.headline)
                    Spacer()
                    legend
                }
                ZStack {
                    TileView(defIndex: t.defIndex, rot: t.rot)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.gold, lineWidth: 2))
                    ForEach(engine.meepleOptions, id: \.self) { f in
                        marker(feature: t.features[f], index: f, color: color)
                    }
                }
                .frame(width: side, height: side)
                HStack(spacing: 12) {
                    Button {
                        engine.undoTile()
                    } label: {
                        Label("Undo tile", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        engine.commitTurn(meeple: nil)
                    } label: {
                        Label("No meeple", systemImage: "forward.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Palette.gold, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Color.black)
                    }
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendDot(Palette.city, "City")
            legendDot(Palette.road, "Road")
            legendDot(Palette.roof, "Abbey")
            legendDot(Palette.fieldDark, "Field")
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.system(size: 10, weight: .medium))
        }
    }

    private func ringColor(_ kind: FeatureKind) -> Color {
        switch kind {
        case .city: return Palette.city
        case .road: return Palette.road
        case .monastery: return Palette.roof
        case .field: return Palette.fieldDark
        }
    }

    private func marker(feature: Feature, index: Int, color: Color) -> some View {
        Button {
            engine.commitTurn(meeple: index)
        } label: {
            ZStack {
                Circle().fill(ringColor(feature.kind).opacity(0.92)).frame(width: 40, height: 40)
                Circle().stroke(Color.white, lineWidth: 2).frame(width: 40, height: 40)
                MeepleView(color: color, size: 24, lying: feature.kind == .field)
            }
        }
        .buttonStyle(.plain)
        .position(x: feature.pos.x * side, y: feature.pos.y * side)
    }
}

// MARK: - Game over

struct GameOverView: View {
    @ObservedObject var engine: GameEngine
    var onAgain: () -> Void
    var onQuit: () -> Void

    var body: some View {
        let ranked = engine.state.players.sorted { $0.score > $1.score }
        let top = ranked.first?.score ?? 0
        let winners = ranked.filter { $0.score == top }
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Palette.gold)
                Text(winners.count == 1 ? "\(winners[0].name) wins!" : "It is a tie!")
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                VStack(spacing: 8) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { idx, p in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.headline)
                                .frame(width: 22)
                                .foregroundStyle(Color.white.opacity(0.6))
                            MeepleView(color: Palette.player(p.colorIndex), size: 26, outline: Color.white.opacity(0.85))
                            Text(p.name).font(.headline)
                            Spacer()
                            Text("\(p.score)")
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundStyle(p.score == top ? Palette.gold : Color.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(p.score == top ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .foregroundStyle(.white)
                HStack(spacing: 12) {
                    Button { onQuit() } label: {
                        Text("Main menu")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    Button { onAgain() } label: {
                        Text("Play again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Palette.gold, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.gold.opacity(0.6), lineWidth: 1.5))
            .padding(24)
        }
    }
}

#Preview {
    ContentView()
}
