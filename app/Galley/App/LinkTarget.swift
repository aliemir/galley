import Foundation
import UniformTypeIdentifiers

/// What a link to a local file may do when clicked. A link in an agent's
/// Markdown must never start an app or a script with one click, so anything
/// that can run is only shown in Finder; documents open in their default
/// app; anything Galley cannot tell asks first.
nonisolated enum LinkTarget: Equatable {
    /// Images, PDFs, text and code, media, office files: opened.
    case document
    /// A folder: shown in Finder.
    case folder
    /// Apps, scripts, installers, workflows, executables: shown, not opened.
    case runnable
    /// Not known to be either: the reader is asked.
    case unknown

    static func of(_ url: URL) -> LinkTarget {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)

        if let type, runnableTypes.contains(where: { type.conforms(to: $0) }) { return .runnable }
        if values?.isDirectory == true {
            guard values?.isPackage == true else { return .folder }
            // A package is a file to the reader: a document one (.rtfd,
            // .pages) opens; any other (an app, a bundle) may hold anything.
            if let type, documentTypes.contains(where: { type.conforms(to: $0) }) { return .document }
            return .runnable
        }
        // HTML runs its scripts in a browser: asked, not opened.
        if let type, type.conforms(to: .html) { return .unknown }
        // A known document stays one even with the execute bit set, as files
        // out of a zip or off a Windows share often have.
        if let type, documentTypes.contains(where: { type.conforms(to: $0) }) { return .document }
        // Anything else that can be executed (a compiled tool, a script
        // with a #! line and no telling extension) runs all the same.
        if FileManager.default.isExecutableFile(atPath: url.path) { return .runnable }
        return .unknown
    }

    static let runnableTypes: [UTType] = [
        .application, .applicationBundle, .executable, .unixExecutable, .script, .shellScript,
        .diskImage, .pluginBundle, .systemPreferencesPane,
        UTType("com.apple.installer-package-archive"), UTType("com.apple.automator-workflow"),
        UTType("com.apple.shortcut"), UTType("com.apple.terminal.shell-script"),
        UTType("com.apple.applescript.script"), UTType("com.apple.applescript.text"),
        UTType("com.apple.inetloc"), UTType("com.apple.web-internet-location"),
    ].compactMap { $0 }

    static let documentTypes: [UTType] = [
        .image, .pdf, .text, .audiovisualContent, .presentation, .spreadsheet,
        .rtf, .rtfd, .flatRTFD, .commaSeparatedText, .json, .xml, .yaml,
        UTType("org.openxmlformats.wordprocessingml.document"), UTType("com.microsoft.word.doc"),
        UTType("com.apple.iwork.pages.sffpages"), UTType("com.apple.iwork.pages.pages"),
    ].compactMap { $0 }
}
