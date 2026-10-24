// What a QR code says, filled in as a form — a link, some text, a Wi-Fi
// network, a contact, an email, a text message or a phone number — and the
// standard payload each makes, the same on both phones (the Android twin's
// QrForms, on the same test rows). The "qr:" payload stays what the code
// is; the form is kept beside it as `qrForm` ({type, fields}) only so it
// opens again filled in.

import Foundation

enum QRForms {

    /// The kinds of content, by the key the form keeps, in the type
    /// picker's order, each with its fields' keys.
    enum ContentType: String, CaseIterable, Identifiable {
        case link, text, wifi, contact, email, sms, phone
        var id: String { rawValue }

        var name: String {
            switch self {
            case .link: return tr("Link")
            case .text: return tr("Text")
            case .wifi: return tr("Wi-Fi")
            case .contact: return tr("Contact")
            case .email: return tr("Email")
            case .sms: return tr("SMS")
            case .phone: return tr("Phone")
            }
        }

        var fields: [String] {
            switch self {
            case .link: return ["url"]
            case .text: return ["text"]
            case .wifi: return ["ssid", "password", "security", "hidden"]
            case .contact: return ["first", "last", "org", "phone", "email", "url"]
            case .email: return ["to", "subject", "body"]
            case .sms: return ["number", "message"]
            case .phone: return ["number"]
            }
        }
    }

    /// A form: its kind and what is typed in each field.
    struct Form: Equatable {
        var kind: ContentType
        var fields: [String: String]

        func field(_ key: String) -> String { fields[key] ?? "" }
    }

    /// The Wi-Fi security choices, as the payload writes them.
    static let security = ["WPA", "WEP", "nopass"]

    /// The payload `form` makes:
    /// - Link: the address as typed; Text: the words as typed.
    /// - Wi-Fi: "WIFI:T:<security>;S:<name>;P:<password>;H:<true|false>;;",
    ///   security WPA unless WEP or nopass, a backslash before each \ ; , :
    ///   and " in the name and the password.
    /// - Contact: a vCard 3.0 — BEGIN:VCARD, VERSION:3.0, N:<last>;<first>,
    ///   FN:<first last>, then ORG, TEL, EMAIL and URL for those filled,
    ///   END:VCARD — lines ended CR LF, a backslash before each \ , and ; in
    ///   a value.
    /// - Email: "mailto:<to>", then "?subject=" and "&body=" for those
    ///   filled ("?body=" with no subject), percent-encoded as UTF-8 (all
    ///   but A–Z, a–z, 0–9 and - . _ ~).
    /// - SMS: "SMSTO:<number>:<message>"; Phone: "tel:<number>".
    /// Every field trimmed of spaces at its ends but Text's, a message's and
    /// an email's body.
    static func payload(_ form: Form) -> String {
        func f(_ key: String) -> String { form.field(key).trimmingCharacters(in: .whitespacesAndNewlines) }
        switch form.kind {
        case .link:
            return f("url")
        case .text:
            return form.field("text")
        case .wifi:
            let kind = security.contains(f("security")) ? f("security") : "WPA"
            let hidden = f("hidden") == "true"
            return "WIFI:T:\(kind);S:\(escaped(f("ssid"), "\\;,:\""));P:\(escaped(f("password"), "\\;,:\""));H:\(hidden);;"
        case .contact:
            var lines = ["BEGIN:VCARD", "VERSION:3.0"]
            lines.append("N:" + escaped(f("last"), "\\,;") + ";" + escaped(f("first"), "\\,;"))
            lines.append("FN:" + escaped([f("first"), f("last")].filter { !$0.isEmpty }.joined(separator: " "), "\\,;"))
            for (key, tag) in [("org", "ORG"), ("phone", "TEL"), ("email", "EMAIL"), ("url", "URL")] where !f(key).isEmpty {
                lines.append(tag + ":" + escaped(f(key), "\\,;"))
            }
            lines.append("END:VCARD")
            return lines.joined(separator: "\r\n")
        case .email:
            let query = [("subject", f("subject")), ("body", form.field("body"))]
                .filter { !$0.1.isEmpty }
                .map { "\($0.0)=\(percentEncoded($0.1))" }
                .joined(separator: "&")
            return "mailto:" + f("to") + (query.isEmpty ? "" : "?" + query)
        case .sms:
            return "SMSTO:" + f("number") + ":" + form.field("message")
        case .phone:
            return "tel:" + f("number")
        }
    }

    /// Whether `form` has what its payload needs: an address, words, a
    /// network name, a name, a recipient or a number.
    static func isFilled(_ form: Form) -> Bool {
        func blank(_ key: String) -> Bool { form.field(key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch form.kind {
        case .link: return !blank("url")
        case .text: return !form.field("text").isEmpty
        case .wifi: return !blank("ssid")
        case .contact: return !blank("first") || !blank("last")
        case .email: return !blank("to")
        case .sms, .phone: return !blank("number")
        }
    }

    /// `el`'s form, when it keeps one of a kind this build knows.
    static func form(of el: Element) -> Form? {
        guard let kept = el.qrForm, let kind = ContentType(rawValue: kept.type) else { return nil }
        return Form(kind: kind, fields: kept.fields)
    }

    /// `el` keeping `form` — its kind's fields with words in them — or none.
    static func with(_ el: Element, _ form: Form?) -> Element {
        var out = el
        out.qrForm = form.map { form in
            var fields: [String: String] = [:]
            for key in form.kind.fields {
                if let value = form.fields[key], !value.isEmpty { fields[key] = value }
            }
            return QRFormFields(type: form.kind.rawValue, fields: fields)
        }
        return out
    }

    /// `s` with a backslash before each of `special`.
    private static func escaped(_ s: String, _ special: String) -> String {
        var out = ""
        for c in s {
            if special.contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    private static func percentEncoded(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var out = ""
        for b in Array(text.utf8) {
            let c = Character(UnicodeScalar(b))
            if b < 128 && (c.isLetter || c.isNumber || c == "-" || c == "." || c == "_" || c == "~") {
                out.append(c)
            } else {
                out.append("%")
                out.append(hex[Int(b >> 4)])
                out.append(hex[Int(b & 15)])
            }
        }
        return out
    }
}
