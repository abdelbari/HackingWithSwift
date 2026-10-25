// A slide's animations as PowerPoint keeps them, its <p:timing>: every
// element's entrance on the slide, all starting together as the slide comes
// up, each after its own delay — the nearest of PowerPoint's own effects to
// each kind (`effect`) — and a recorded motion path as a custom one
// (p:animMotion) along its points. Exits, loops and a kind with no near
// effect are left out; the shapes are simply there. The Android twin's
// PptxAnimations, rule for rule.
//
// A clip goes out as a video PowerPoint plays on a click on it (`videoNvPr`,
// `videoClick`): its own interactive sequence in the timing, which toggles
// it playing and paused, and a media node for it — the same markup on both
// phones, character for character.

import Foundation

enum PptxAnimations {

    /// One of PowerPoint's entrance effects: its preset number and subtype,
    /// and the filter its p:animEffect uses — none for one that only moves
    /// or appears.
    struct Effect: Equatable {
        var preset: Int
        var subtype: Int
        var filter: String?
    }

    /// The built-in entrance nearest each kind: Fade for a fade, a breathe,
    /// a reveal of text and a draw-on; Float In for a rise, a drift and a
    /// line of type rising; Fly In from the right or the left for the
    /// slides; Zoom for a pop and a grow; Wipe from the left for a wipe; and
    /// Grow & Turn for a tumble. Nil for a loop, a photo's motion and a
    /// path, which is written as its own (`motion`).
    static func effect(_ kind: String) -> Effect? {
        switch kind {
        case "fade", "breathe", "typewriter", "words", "letterPop", ElementAnimation.draw:
            return Effect(preset: 10, subtype: 0, filter: "fade")
        case "rise", "drift", "lineRise", ElementAnimation.baseline:
            return Effect(preset: 42, subtype: 0, filter: "fade")
        case "slideLeft": return Effect(preset: 2, subtype: 2, filter: nil)
        case "slideRight": return Effect(preset: 2, subtype: 8, filter: nil)
        case "pop", ElementAnimation.grow: return Effect(preset: 53, subtype: 16, filter: "fade")
        case "wipe": return Effect(preset: 22, subtype: 8, filter: "wipe(right)")
        case "tumble": return Effect(preset: 31, subtype: 0, filter: "fade")
        default: return nil
        }
    }

    /// A path's points as PowerPoint's motion path: relative moves from
    /// where the shape sits, as shares of a slide `slideW` by `slideH` page
    /// units — "M x y L x y … E" — each point less the last, so it ends
    /// where the shape rests.
    static func motion(_ points: [MotionPath.Point], slideW: Double, slideH: Double) -> String {
        guard let last = points.last, slideW > 0, slideH > 0 else { return "M 0 0 E" }
        let steps = points.enumerated().map { i, p in
            (i == 0 ? "M " : "L ") + num((p.dx - last.dx) / slideW) + " " + num((p.dy - last.dy) / slideH)
        }
        return steps.joined(separator: " ") + " E"
    }

    /// A clip's relationships: the video it shows, and the media it plays.
    static let videoRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/video"
    static let mediaRel = "http://schemas.microsoft.com/office/2007/relationships/media"

    /// A clip's click, in its cNvPr's hlinkClick: play or pause the media.
    static let videoClick = "r:id=\"\" action=\"ppaction://media\""

    /// A clip's p:nvPr: the video (`video`, its relationship id) and, as
    /// PowerPoint 2010 on keeps it, the media embedded (`media`).
    static func videoNvPr(video: String, media: String) -> String {
        let ext = "<p:ext uri=\"{DAA4B4D4-6D71-4841-9C94-3DA1E494A21F}\">"
            + "<p14:media xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" r:embed=\"\(media)\"/></p:ext>"
        return "<p:nvPr><a:videoFile r:link=\"\(video)\"/><p:extLst>" + ext + "</p:extLst></p:nvPr>"
    }

    /// The <p:timing> for `shapes` — each shape's id on the slide and the
    /// element it is — on a slide `slideW` by `slideH` page units, and the
    /// `clips` on it by shape id, each played and paused by a click on it;
    /// empty when none of them comes in by an effect PowerPoint has and
    /// there is no clip.
    static func timing(_ shapes: [(id: Int, el: Element)], slideW: Double, slideH: Double, clips: [Int] = []) -> String {
        var node = 4
        var effects = ""
        for (spid, el) in shapes {
            guard let anim = el.animation else { continue }
            let delay = ms((el.timing?.start ?? 0) + anim.delay)
            if anim.kind == ElementAnimation.pathKind, MotionPath.travels(anim.path) {
                node += 1
                let outer = node
                node += 1
                let move = node
                effects += "<p:par><p:cTn id=\"\(outer)\" presetID=\"0\" presetClass=\"path\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"withEffect\">"
                effects += "<p:stCondLst><p:cond delay=\"\(delay)\"/></p:stCondLst><p:childTnLst>"
                effects += "<p:animMotion origin=\"layout\" path=\"\(motion(anim.path ?? [], slideW: slideW, slideH: slideH))\" pathEditMode=\"relative\" ptsTypes=\"\">"
                effects += "<p:cBhvr><p:cTn id=\"\(move)\" dur=\"\(ms(anim.playedFor))\" fill=\"hold\"/><p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl>"
                effects += "<p:attrNameLst><p:attrName>ppt_x</p:attrName><p:attrName>ppt_y</p:attrName></p:attrNameLst></p:cBhvr></p:animMotion>"
                effects += "</p:childTnLst></p:cTn></p:par>"
                continue
            }
            guard let found = effect(anim.kind) else { continue }
            node += 1
            let outer = node
            node += 1
            let set = node
            effects += "<p:par><p:cTn id=\"\(outer)\" presetID=\"\(found.preset)\" presetClass=\"entr\" presetSubtype=\"\(found.subtype)\" fill=\"hold\" nodeType=\"withEffect\">"
            effects += "<p:stCondLst><p:cond delay=\"\(delay)\"/></p:stCondLst><p:childTnLst>"
            effects += "<p:set><p:cBhvr><p:cTn id=\"\(set)\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst></p:cTn>"
            effects += "<p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl><p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr>"
            effects += "<p:to><p:strVal val=\"visible\"/></p:to></p:set>"
            if let filter = found.filter {
                node += 1
                effects += "<p:animEffect transition=\"in\" filter=\"\(filter)\"><p:cBhvr><p:cTn id=\"\(node)\" dur=\"\(ms(anim.duration))\"/>"
                effects += "<p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl></p:cBhvr></p:animEffect>"
            }
            effects += "</p:childTnLst></p:cTn></p:par>"
        }
        guard !effects.isEmpty || !clips.isEmpty else { return "" }
        // One click group, begun with the slide itself.
        let root = "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst>"
        var main = ""
        if effects.isEmpty {
            node = 1
        } else {
            main = mainSequence(effects)
        }
        // Each clip's click sequence, then each clip's media node.
        var triggers = ""
        for spid in clips {
            triggers += clickSequence(spid, from: node)
            node += 5
        }
        for spid in clips {
            node += 1
            triggers += "<p:video><p:cMediaNode vol=\"80000\"><p:cTn id=\"\(node)\" fill=\"hold\" display=\"0\">"
            triggers += "<p:stCondLst><p:cond delay=\"indefinite\"/></p:stCondLst></p:cTn><p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl></p:cMediaNode></p:video>"
        }
        let closeRoot = "</p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
        return root + main + triggers + closeRoot
    }

    /// The slide's one click group of entrances, `effects`, begun with the
    /// slide itself.
    private static func mainSequence(_ effects: String) -> String {
        let sequence = "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>"
        let click = "<p:par><p:cTn id=\"3\" fill=\"hold\"><p:stCondLst><p:cond delay=\"indefinite\"/>"
            + "<p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"2\"/></p:cond></p:stCondLst><p:childTnLst>"
        let together = "<p:par><p:cTn id=\"4\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>"
        let closeGroups = "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>"
        let prev = "<p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>"
        let next = "<p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst>"
        let closeSequence = "</p:childTnLst></p:cTn>" + prev + next + "</p:seq>"
        return [sequence, click, together, effects, closeGroups, closeSequence].joined()
    }

    /// Clip `spid`'s click sequence, its nodes numbered on from `node`:
    /// a click on it toggles it playing and paused.
    private static func clickSequence(_ spid: Int, from node: Int) -> String {
        let target = "<p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl>"
        let click = "<p:cond evt=\"onClick\" delay=\"0\">\(target)</p:cond>"
        let now = "<p:stCondLst><p:cond delay=\"0\"/></p:stCondLst>"
        var out = "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"\(node + 1)\" restart=\"whenNotActive\" fill=\"hold\" "
        out += "evtFilter=\"cancelBubble\" nodeType=\"interactiveSeq\">"
        out += "<p:stCondLst>\(click)</p:stCondLst><p:endSync evt=\"end\" delay=\"0\"><p:rtn val=\"all\"/></p:endSync><p:childTnLst>"
        out += "<p:par><p:cTn id=\"\(node + 2)\" fill=\"hold\">\(now)<p:childTnLst>"
        out += "<p:par><p:cTn id=\"\(node + 3)\" fill=\"hold\">\(now)<p:childTnLst>"
        out += "<p:par><p:cTn id=\"\(node + 4)\" presetID=\"2\" presetClass=\"mediacall\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"clickEffect\">"
        out += "\(now)<p:childTnLst><p:cmd type=\"call\" cmd=\"togglePause\">"
        out += "<p:cBhvr><p:cTn id=\"\(node + 5)\" dur=\"1\" fill=\"hold\"/>\(target)</p:cBhvr></p:cmd>"
        out += "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>"
        out += "</p:childTnLst></p:cTn><p:nextCondLst>\(click)</p:nextCondLst></p:seq>"
        return out
    }

    private static func ms(_ seconds: Double) -> Int {
        Int((max(0, seconds) * 1000).rounded())
    }

    /// A share to four places, no trailing zeros, never -0.
    static func num(_ v: Double) -> String {
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" || s.isEmpty ? "0" : s
    }
}
