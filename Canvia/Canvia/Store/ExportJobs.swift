// The Export sheet's rows as queue jobs (ExportQueue). Each takes what it
// needs when it is made — the snapshot of the design and the settings as
// they stand — and nothing from the sheet, so it renders the same whether
// the sheet is still up, closed, or the app is in the background.

import Foundation

@MainActor
enum ExportJobs {

    typealias Work = ExportQueue.Work

    /// PNG or JPEG, a file a page.
    static func pictures(_ snapshot: ExportSnapshot, format: DesignExporter.RasterFormat, scale: Double,
                         longEdge: Double, quality: Double, transparent: Bool) -> Work {
        { report in
            let urls = try await DesignExporter.exportPages(
                design: snapshot.design, range: snapshot.range, current: snapshot.current,
                format: format, scale: scale, longEdge: longEdge, quality: quality,
                // JPEG has no alpha channel to be transparent in.
                transparent: transparent && format == .png, captionTime: snapshot.captionTime, progress: report)
            return ExportQueue.Result(urls: urls)
        }
    }

    /// The pictures into Photos rather than the share sheet. Each is counted
    /// as it goes in, and what went in is said even after a Cancel.
    static func picturesToPhotos(_ snapshot: ExportSnapshot, format: DesignExporter.RasterFormat, scale: Double,
                                 longEdge: Double, quality: Double, transparent: Bool) -> Work {
        let render = pictures(snapshot, format: format, scale: scale, longEdge: longEdge,
                              quality: quality, transparent: transparent)
        return { report in
            let urls = try await render(report).urls
            let outcome = try await PhotoSaver.save(urls)
            return ExportQueue.Result(photosNote: outcome.message, photosSaved: outcome.anySaved)
        }
    }

    /// The video into Photos. Music that would not go in leaves a silent
    /// video, and says so.
    static func movieToPhotos(_ snapshot: ExportSnapshot, settings: MovieExporter.Settings) -> Work {
        let render = movie(snapshot, settings: settings)
        return { report in
            let made = try await render(report)
            let outcome = try await PhotoSaver.save(made.urls)
            if outcome.cancelled && !outcome.anySaved { return ExportQueue.Result() }
            var text = outcome.anySaved ? tr("Saved the video to your photos.") : tr("Couldn't save to your photos.")
            if made.musicLost { text += " " + ExportChoices.musicLost }
            return ExportQueue.Result(photosNote: text, photosSaved: outcome.anySaved)
        }
    }

    /// The GIF into Photos, which keeps it moving, counted as the
    /// pictures are.
    static func gifToPhotos(_ snapshot: ExportSnapshot, settings: MovieExporter.Settings) -> Work {
        let render = gif(snapshot, settings: settings)
        return { report in
            let urls = try await render(report).urls
            let outcome = try await PhotoSaver.save(urls)
            return ExportQueue.Result(photosNote: outcome.message, photosSaved: outcome.anySaved)
        }
    }

    /// The MP4. The picture is kept when the music will not go under it,
    /// and that is said beside the share. With `captions`, the .srt of the
    /// pages played goes with it (`captionsFile`).
    static func movie(_ snapshot: ExportSnapshot, settings: MovieExporter.Settings, captions: Bool = false) -> Work {
        { report in
            let url = DesignExporter.fileURL(for: snapshot.design, ext: "mp4")
            let made = try await MovieExporter.exportMP4(design: snapshot.design, settings: settings,
                                                         range: snapshot.range, current: snapshot.current,
                                                         to: url, progress: report)
            var urls = [url]
            if captions, let srt = try captionsFile(snapshot) { urls.append(srt) }
            return ExportQueue.Result(urls: urls, musicLost: made.musicLost)
        }
    }

    /// The captions of the pages the video plays as one .srt beside it —
    /// every page's cues moved on by where its page starts in the film
    /// (Captions.film) — or nil when there are none.
    static func captionsFile(_ snapshot: ExportSnapshot) throws -> URL? {
        let design = snapshot.design
        let pages = MovieExporter.playedPages(design: design, range: snapshot.range, current: snapshot.current)
        let cues = Captions.film(design, indices: pages) { Timeline.hold(of: design.pages[$0], in: design) }
        guard !cues.isEmpty else { return nil }
        let url = DesignExporter.fileURL(for: design, ext: "srt")
        try Captions.srt(cues).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func gif(_ snapshot: ExportSnapshot, settings: MovieExporter.Settings) -> Work {
        { report in
            let url = DesignExporter.fileURL(for: snapshot.design, ext: "gif")
            try await MovieExporter.exportGIF(design: snapshot.design, settings: settings, range: snapshot.range,
                                              current: snapshot.current, to: url, progress: report)
            return ExportQueue.Result(urls: [url])
        }
    }

    static func pdf(_ snapshot: ExportSnapshot, flatten: Bool, notes: Bool = false, compress: Bool = false,
                    bookmarks: Bool = true) -> Work {
        { report in
            let url = DesignExporter.fileURL(for: snapshot.design, ext: "pdf")
            try await DesignExporter.exportPDF(design: snapshot.design, range: snapshot.range,
                                               current: snapshot.current, flatten: flatten, notes: notes,
                                               compress: compress, bookmarks: bookmarks, to: url, progress: report)
            return ExportQueue.Result(urls: [url])
        }
    }

    /// The print-ready PDF, to share; with `printing`, handed to the
    /// printer instead.
    static func printPDF(_ snapshot: ExportSnapshot, options: PrintLayout.Options, flatten: Bool,
                         printing: Bool, bookmarks: Bool = true) -> Work {
        { report in
            let url = DesignExporter.fileURL(for: snapshot.design, ext: "pdf", suffix: printing ? "" : "-print")
            if options.colourProfile == .cmyk && !printing {
                // For a print shop: flattened, in press ink. A printer
                // here is handed RGB, as ever.
                try await DesignExporter.exportCmykPrintPDF(design: snapshot.design, range: snapshot.range,
                                                            current: snapshot.current, options: options,
                                                            bookmarks: bookmarks, to: url, progress: report)
            } else {
                try await DesignExporter.exportPrintPDF(design: snapshot.design, range: snapshot.range,
                                                        current: snapshot.current, options: options,
                                                        flatten: flatten, bookmarks: bookmarks, to: url, progress: report)
            }
            guard printing else { return ExportQueue.Result(urls: [url]) }
            let size = snapshot.design.size(at: snapshot.pages.first ?? snapshot.current)
            let title = snapshot.design.title
            return ExportQueue.Result(print: ExportQueue.PrintRequest(
                url: url, jobName: title.isEmpty ? tr("Canvia design") : title, landscape: size.width > size.height))
        }
    }

    /// The deck as a .pptx named after the design, its styled text
    /// editable (the closest match) or the picture of its exact look.
    static func powerPoint(_ snapshot: ExportSnapshot, styled: Bool = true) -> Work {
        { report in
            let url = DesignExporter.fileURL(for: snapshot.design, ext: PptxExporter.fileExtension)
            try await PptxExporter.export(design: snapshot.design, range: snapshot.range,
                                          current: snapshot.current, to: url, styled: styled, progress: report)
            return ExportQueue.Result(urls: [url])
        }
    }

    /// One .svg a page, shared together.
    static func svg(_ snapshot: ExportSnapshot) -> Work {
        { report in
            let urls = try DesignExporter.exportSVGs(design: snapshot.design, range: snapshot.range,
                                                     current: snapshot.current)
            report(1)
            return ExportQueue.Result(urls: urls)
        }
    }

    /// The pages as one web page: index.html, or a .zip of it and its
    /// clips (HTMLExporter).
    static func html(_ snapshot: ExportSnapshot, settings: HTMLExporter.Settings) -> Work {
        { report in
            let url = try HTMLExporter.export(snapshot.design, pages: snapshot.pages, settings: settings)
            report(1)
            return ExportQueue.Result(urls: [url])
        }
    }

    /// The design and its photos as a Canvia design file. Gathered on the
    /// main actor, where library photos are drawn; written out away from
    /// it, since turning every photo and clip into base64 takes long
    /// enough, on a design with clips, to freeze the app.
    static func designFile(_ design: Design) -> Work {
        { report in
            let url = DesignExporter.fileURL(for: design, ext: DesignPackage.ext)
            let contents = DesignPackage.contents(of: design)
            try Task.checkCancellation()
            try await Task.detached(priority: .userInitiated) {
                try DesignPackage.encode(contents).write(to: url)
            }.value
            report(1)
            return ExportQueue.Result(urls: [url])
        }
    }
}
