// A QR code's content as a form, and a barcode's words, in the Android
// twin's words: the type picker — Link, Text, Wi-Fi, Contact, Email, SMS,
// Phone — and its fields, which make the standard payload (QRForms); a
// barcode's kind and words, saying why as they are typed when they cannot
// be that kind (Barcodes.encode). The composer adds either to the page; the
// code sheet edits them in place with the same rows.

import SwiftUI

/// The type picker and the fields of a QR form.
struct QRFormRows: View {
    @Binding var form: QRForms.Form

    var body: some View {
        Picker("Type", selection: $form.kind) {
            ForEach(QRForms.ContentType.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.menu)
        ForEach(form.kind.fields, id: \.self) { key in
            row(key)
        }
    }

    @ViewBuilder
    private func row(_ key: String) -> some View {
        switch key {
        case "security":
            Picker("Type", selection: field(key, default: "WPA")) {
                ForEach(QRForms.security, id: \.self) { option in
                    Text(option == "nopass" ? tr("No password") : option).tag(option)
                }
            }
        case "hidden":
            Toggle("Hidden network", isOn: Binding(get: { form.field(key) == "true" },
                                                   set: { form.fields[key] = $0 ? "true" : "false" }))
        default:
            TextField(Self.label(form.kind, key), text: field(key, default: ""), axis: Self.long(key) ? .vertical : .horizontal)
                .lineLimit(Self.long(key) ? 1...5 : 1...1)
                .keyboardType(Self.keyboard(key))
                .textInputAutocapitalization(Self.words(key) ? .sentences : .never)
                .autocorrectionDisabled(!Self.words(key))
        }
    }

    private func field(_ key: String, default value: String) -> Binding<String> {
        Binding(get: { form.fields[key] ?? value }, set: { form.fields[key] = $0 })
    }

    /// What a field is called, in the type picker's words.
    static func label(_ kind: QRForms.ContentType, _ key: String) -> String {
        switch key {
        case "url": return kind == .contact ? tr("Website") : tr("Link")
        case "text": return tr("Text")
        case "ssid": return tr("Network name")
        case "password": return tr("Password")
        case "first": return tr("First name")
        case "last": return tr("Last name")
        case "org": return tr("Organisation")
        case "phone": return tr("Phone")
        case "email": return tr("Email")
        case "to": return tr("To")
        case "subject": return tr("Subject")
        case "body", "message": return tr("Message")
        case "number": return tr("Number")
        default: return key
        }
    }

    /// Whether a field holds words to read — a message, some text — rather
    /// than an address, a name to keep as typed, or a number.
    private static func words(_ key: String) -> Bool {
        ["text", "body", "message", "subject", "first", "last", "org"].contains(key)
    }

    private static func long(_ key: String) -> Bool { ["text", "body", "message"].contains(key) }

    /// A link's, an address's and a number's keyboard; words' as words.
    private static func keyboard(_ key: String) -> UIKeyboardType {
        switch key {
        case "url": return .URL
        case "email", "to": return .emailAddress
        case "phone", "number": return .phonePad
        default: return .default
        }
    }
}

/// A barcode's kind and words, and under them why they are no code of that
/// kind yet.
struct BarcodeRows: View {
    @Binding var kind: Barcodes.Symbology
    @Binding var text: String

    var body: some View {
        Picker("Kind", selection: $kind) {
            ForEach(Barcodes.Symbology.allCases) { Text(verbatim: $0.name).tag($0) }
        }
        .pickerStyle(.segmented)
        let digits = kind == .ean13 || kind == .upca
        TextField(digits ? tr("Digits") : tr("Text"), text: $text)
            .keyboardType(digits ? .numberPad : .asciiCapable)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        if let reason = Self.reason(kind, text) {
            Text(reason)
                .font(.footnote)
                .foregroundStyle(Color(.systemRed))
        }
    }

    /// Why `text` is no barcode of `kind`, once something is typed.
    static func reason(_ kind: Barcodes.Symbology, _ text: String) -> String? {
        text.isEmpty ? nil : Barcodes.encode(kind, text).reason
    }
}

/// A QR code from a form, or a barcode, added to the page.
struct CodeComposerSheet: View {
    let store: DesignStore
    @State private var barcode: Bool
    @State private var form: QRForms.Form
    @State private var kind: Barcodes.Symbology = .code128
    @State private var words = ""
    @Environment(\.dismiss) private var dismiss

    /// Opened on a barcode, or on a QR code's form of `kind`.
    init(store: DesignStore, barcode: Bool, kind: QRForms.ContentType = .link) {
        self.store = store
        _barcode = State(initialValue: barcode)
        _form = State(initialValue: QRForms.Form(kind: kind, fields: [:]))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $barcode) {
                    Text("QR code").tag(false)
                    Text("Barcode").tag(true)
                }
                .pickerStyle(.segmented)
                if barcode {
                    Section {
                        BarcodeRows(kind: $kind, text: $words)
                    } footer: {
                        Text("EAN-13 and UPC-A take digits, their check digit worked out for you; Code 128 and Code 39 take words too.")
                    }
                } else {
                    Section {
                        QRFormRows(form: $form)
                    } footer: {
                        if let problem = qrProblem { Text(problem).foregroundStyle(Color(.systemRed)) }
                    }
                }
            }
            .navigationTitle(barcode ? tr("Add a barcode") : tr("Add a QR code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { if add() { dismiss() } }
                        .disabled(barcode ? Barcodes.encode(kind, words).widths == nil : !QRForms.isFilled(form))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Why the form's payload cannot be a code, when it is filled in.
    private var qrProblem: String? {
        guard QRForms.isFilled(form) else { return nil }
        return CodeGenerator.problem(with: QRForms.payload(form))
    }

    /// The code on the page, as one step: a QR code square, 0.3 of the
    /// page's shorter side, its form kept beside it; a barcode half that
    /// side wide and half that tall, its payload as the code reads it (an
    /// EAN-13's with its check digit, a Code 39's in capitals) — as the
    /// Android twin sizes them.
    private func add() -> Bool {
        let shorter = min(store.pageWidth, store.pageHeight)
        if barcode {
            guard let readable = Barcodes.encode(kind, words).readable else {
                store.buzz(.reject)
                return false
            }
            let size = Barcodes.newSize(shorter)
            var el = Element.image(Barcodes.source(kind, readable), w: size.width, h: size.height)
            el.radius = 0
            guard store.add(el) else { return false }
            ElementSearch.remember(.qr, "qr")
            return true
        }
        let payload = QRForms.payload(form)
        guard QRForms.isFilled(form), CodeGenerator.modules(for: payload) != nil else {
            store.buzz(.reject)
            return false
        }
        let side = (shorter * 0.3).rounded()
        guard store.add(QRForms.with(.image(CodeGenerator.source(for: payload), w: side, h: side), form)) else { return false }
        ElementSearch.remember(.qr, "qr")
        return true
    }
}
