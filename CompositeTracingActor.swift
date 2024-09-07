import Foundation
import SwiftUI

actor CompositeTracingActor {
    
    private(set) var combinedTracings: [SendableCombinedTracing] = []
   
    /**
    Given all tracings for a sun map. determine where they overlap, and where they do, determine the combined duration for the area overlapped.
     Each overlap becomes a new SendableCombinedTracing struct that will be drawn as a path on the composite tracing view. Also, each individual tracing
     is added as a SendableCombinedTracing and drawn as well.
     */
    func build(_ tracings: [SendableTracing]) {
        var combinedTracings = [SendableCombinedTracing]()
        var allTracings: [SendableTracing] = [] // all tracings for the sun map
        
        // overlaps stored as indices (i.e. tracings[i] intersects with tracings[j] where j in intersectionMapping[i]
        // built as we iterate through tracings
        var intersectionMapping: [[Int]] = []
        
        let indices = tracings.indices
        
        // loop through all tracings
        for i in indices {
            let iTracing = tracings[i]
            
            // add empty array that will contain all tracings that it inersects with before it in the array
            intersectionMapping.append([])
            
            // this tracing by itself will be shown in the composite
            allTracings.append(iTracing)
            
            // for each tracing before it
            for j in stride(from: i - 1, through: 0, by: -1) {
                let jTracing = tracings[j]
                
                // these are not enabled to intersect, since they are tracings on the same image
                if jTracing.minuteInterval == iTracing.minuteInterval {
                    continue
                }
                
                // identify the overlap to build the overlap chain(s)
                if iTracing.intersects(jTracing) {
                    intersectionMapping[i].append(j)
                }
            }
            // the single tracing itself is to be drawn on the composite
            if let selfTracing = SendableCombinedTracing.newInstance(tracings: [iTracing]) {
                combinedTracings.append(selfTracing)
            }
            // get each 'overlap chain' where all tracings in the chain overlap each other (note: chain stores indeces of tracings)
            for chain in getIntersectionChains(chain: [i], intersectionMapping: intersectionMapping) {
                if let combinedTracing = SendableCombinedTracing.newInstance(tracings: chain.map({ tracings[$0] })) {
                    combinedTracings.append(combinedTracing)
                }
            }
        }
        
        // sort so that the highest duration paths are drawn on top
        self.combinedTracings = combinedTracings.sorted(by: { $0.duration < $1.duration })
    }
    
    
    // finds all combinations of intersections
    nonisolated private func getIntersectionChains(chain: [Int], intersectionMapping: [[Int]]) -> [[Int]] {
        var res = [[Int]]()
        
        // for each tracing (index) intersected with the first element in the chain that also intersects with the last element in the chain
        // (i.e. we care about: how many layers can we pile on top of the first tracing in the chain?)
        for intersect in intersectionMapping[chain.first!].intersection(intersectionMapping[chain.last!]) {
            var newChain = chain
            newChain.append(intersect)
            
            // each addition to the chain is something we care to return
            res.append(newChain)
            
            // see how many layers overlap - take it as far as we can
            res.append(contentsOf: getIntersectionChains(chain: newChain, intersectionMapping: intersectionMapping))
        }
        return res
    }
}




/**
 This is a tracing of sunlight overtop of an image of a garden made by draggable nodes forming a shape.
 */
struct SendableTracing {
    let minuteInterval: Int
    let durationInMinutes: Double
    let shadowPct: Double
    let id: UUID
    let nodes: [CGPoint]
    let relativeFrame: CGSize
    
    func path(in frame: CGSize? = nil) -> Path {
        var nodes = self.nodes
        if let frame {
            nodes = nodes.adjust(fromFrame: self.relativeFrame, toFrame: frame)
        }
        return nodes.edgePath
    }
   
    func intersects(_ other: SendableTracing) -> Bool {
        self.path().optionalIntersection(other.path(in: self.relativeFrame)) != nil
    }
}


/**
Say a tracing for the 9:00am sun map image overlaps a tracing for the 10:00am sun map image.
 This overlap now represents 2 hours of sunlight. So, we store the combination in this struct.
 There can be any number of overlapping tracings: 1...n
 */
struct SendableCombinedTracing: Identifiable {
    let id = UUID()
    let intersectTracings: [SendableTracing]
    let duration: Double
    
    private init(intersectTracings: [SendableTracing]) {
        self.intersectTracings = intersectTracings
        self.duration = intersectTracings.durationInMinutes
    }
    
    public static func newInstance(tracings: [SendableTracing]) -> SendableCombinedTracing? {
        guard tracings.allIntersect else { return nil }
        return SendableCombinedTracing(
            intersectTracings: tracings
        )
    }
}


extension Array where Element == CGPoint {
    
    func adjust(fromFrame: CGSize, toFrame: CGSize) -> [CGPoint] {
        self.map({ $0.adjust(fromFrame: fromFrame, toFrame: toFrame) })
    }
    
    var edgePath: Path {
        var p = Path()
        guard !self.isEmpty else { return p }
        p.addLines(self)
        p.move(to: self.last!)
        p.addLine(to: self.first!)
        return p
    }
    
}

extension CGPoint {
    
    func adjust(fromFrame: CGSize, toFrame: CGSize) -> CGPoint {
        guard fromFrame.width != 0, fromFrame.height != 0 else {
            return self
        }
        
        return .init(
            x: self.x * toFrame.width / fromFrame.width,
            y: self.y * toFrame.height / fromFrame.height
        )
    }
    
}

extension Path {
    
    func optionalIntersection(_ other: Path?) -> Path? {
        guard let other else { return nil }
        let intersect = self.intersection(other)
        return intersect.description.isEmpty ? nil : intersect
    }
    
    private static func intersectAll(paths: [Path], curIdx: Int) -> Path? {
        if paths.isEmpty { return Path() }
        if paths.count == 1 { return paths[0] }
        if curIdx == paths.count - 2 {
            return paths[curIdx].optionalIntersection(paths[curIdx + 1])
        }
        return paths[curIdx].optionalIntersection(intersectAll(paths: paths, curIdx: curIdx + 1))
    }
    
    static func intersection(of paths: [Path]) -> Path? {
        return intersectAll(paths: paths, curIdx: 0)
    }
    
}

extension Array where Element == SendableTracing {
    
    var durationInMinutes: Double {
        var res = 0.0
        var map = [Int:[Double]]()
        for t in self {
            map[t.minuteInterval] = (map[t.minuteInterval] ?? []).appending(element: t.durationInMinutes)
        }
        for (_, value) in map {
            res += value.average
        }
        return res
    }
    
    var allIntersect: Bool {
        self.isEmpty
        ? false
        : Path.intersection(of: self.map({ $0.path(in: self[0].relativeFrame) })) != nil
    }
    
}

extension Array {
    func appending(element: Element) -> Self {
        var res = self
        res.append(element)
        return res
    }
}

extension Array where Element == Double {
    var average: Double {
        sum / Double(count)
    }
    
    var sum: Element {
        var res: Element = 0
        for num in self { res = res + num }
        return res
    }
}


extension Array where Element: Equatable {
    func intersection(_ other: Array) -> [Element] {
        var res = [Element]()
        for e in other {
            if self.contains(where: {$0 == e}) {
                res.append(e)
            }
        }
        return res
    }
}
