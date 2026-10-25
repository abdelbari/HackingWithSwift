// A clip in a PowerPoint (PptxExporter, PptxAnimations): its poster, its
// file whole after it, and a click on it that plays and pauses it. The
// timing row is shared: the Android twin's PptxVideoTest holds the same
// XML, character for character.

import XCTest
@testable import Canvia

final class PptxVideoTests: XCTestCase {

    private var clipElement: Element {
        var el = Element.image("video:v1@2.00", w: 320, h: 180)
        el.id = "c"
        el.x = 40
        el.y = 30
        return el
    }

    private var deck: Design {
        var design = Design(title: "Deck", width: 800, height: 600)
        design.pages[0].elements = [clipElement]
        return design
    }

    func testSharedAClipPlaysAndPausesOnAClickOnIt() {
        let xml = [
            "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\">",
            "<p:childTnLst><p:seq concurrent=\"1\" nextAc=\"seek\">",
            "<p:cTn id=\"2\" restart=\"whenNotActive\" fill=\"hold\" evtFilter=\"cancelBubble\" nodeType=\"interactiveSeq\">",
            "<p:stCondLst><p:cond evt=\"onClick\" delay=\"0\"><p:tgtEl><p:spTgt spid=\"5\"/></p:tgtEl></p:cond>",
            "</p:stCondLst><p:endSync evt=\"end\" delay=\"0\"><p:rtn val=\"all\"/></p:endSync><p:childTnLst><p:par>",
            "<p:cTn id=\"3\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:par>",
            "<p:cTn id=\"4\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:par>",
            "<p:cTn id=\"5\" presetID=\"2\" presetClass=\"mediacall\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"clickEffect\">",
            "<p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:cmd type=\"call\" cmd=\"togglePause\">",
            "<p:cBhvr><p:cTn id=\"6\" dur=\"1\" fill=\"hold\"/><p:tgtEl><p:spTgt spid=\"5\"/></p:tgtEl></p:cBhvr></p:cmd>",
            "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>",
            "</p:childTnLst></p:cTn><p:nextCondLst><p:cond evt=\"onClick\" delay=\"0\"><p:tgtEl><p:spTgt spid=\"5\"/>",
            "</p:tgtEl></p:cond></p:nextCondLst></p:seq><p:video><p:cMediaNode vol=\"80000\">",
            "<p:cTn id=\"7\" fill=\"hold\" display=\"0\"><p:stCondLst><p:cond delay=\"indefinite\"/></p:stCondLst>",
            "</p:cTn><p:tgtEl><p:spTgt spid=\"5\"/></p:tgtEl></p:cMediaNode></p:video></p:childTnLst></p:cTn>",
            "</p:par></p:tnLst></p:timing>",
        ].joined()
        XCTAssertEqual(PptxAnimations.timing([], slideW: 1000, slideH: 500, clips: [5]), xml)
        XCTAssertEqual(PptxAnimations.timing([], slideW: 1000, slideH: 500), "")
        let nvPr = "<p:nvPr><a:videoFile r:link=\"rId3\"/><p:extLst><p:ext uri=\"{DAA4B4D4-6D71-4841-9C94-3DA1E494A21F}\">"
            + "<p14:media xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" r:embed=\"rId4\"/></p:ext></p:extLst></p:nvPr>"
        XCTAssertEqual(PptxAnimations.videoNvPr(video: "rId3", media: "rId4"), nvPr)
    }

    func testAClipGoesOutAsItsPosterAndItsFilePlayedOnAClick() {
        let design = deck
        let planned = PptxExporter.media(design: design, page: design.pages[0], firstImage: 1)
        XCTAssertEqual(planned.map(\.name), ["image1.png", "media2.mp4"])
        XCTAssertEqual(planned.last?.source, .clip("video:v1"))
        XCTAssertTrue(PptxExporter.contentTypes(noted: [false]).contains("<Default Extension=\"mp4\" ContentType=\"video/mp4\"/>"))
        let parts = PptxExporter.slide(design: design, page: design.pages[0], number: 1, previous: nil, drawn: planned)
        let picture = "<p:cNvPr id=\"2\" name=\"c\"><a:hlinkClick r:id=\"\" action=\"ppaction://media\"/></p:cNvPr><p:cNvPicPr/>"
            + PptxAnimations.videoNvPr(video: "rId3", media: "rId4")
        XCTAssertTrue(parts.xml.contains(picture), parts.xml)
        XCTAssertTrue(parts.xml.contains(PptxAnimations.timing([], slideW: 1, slideH: 1, clips: [2])))
        let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        XCTAssertTrue(parts.rels.contains("<Relationship Id=\"rId2\" Type=\"\(base)image\" Target=\"../media/image1.png\"/>"))
        XCTAssertTrue(parts.rels.contains("<Relationship Id=\"rId3\" Type=\"\(base)video\" Target=\"../media/media2.mp4\"/>"))
        XCTAssertTrue(parts.rels.contains("<Relationship Id=\"rId4\" Type=\"http://schemas.microsoft.com/office/2007/relationships/media\" "
            + "Target=\"../media/media2.mp4\"/>"))
    }

    func testAClipWhoseFileIsNotOnThePhoneIsItsPosterAlone() {
        let design = deck
        let poster = PptxExporter.MediaPart(name: "image1.png", source: .element(design.pages[0].elements[0]))
        let parts = PptxExporter.slide(design: design, page: design.pages[0], number: 1, previous: nil, drawn: [poster])
        XCTAssertTrue(parts.xml.contains("<p:cNvPr id=\"2\" name=\"c\"/><p:cNvPicPr/><p:nvPr/>"), parts.xml)
        XCTAssertFalse(parts.xml.contains("<p:timing>"))
    }
}
