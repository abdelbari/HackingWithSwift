#!/usr/bin/env python3
"""Regenerate both phones' emoji catalogue.

    tools/generate_emoji.py [path/to/ios/Content]

Writes core/src/main/resources/com/canvia/core/content/emoji.json and, given
a folder, the same file there for the iOS twin to bundle. Nothing is
downloaded: names come from Python's own Unicode database (unicodedata), and
which code points are emoji, which take a skin tone, and the flags' country
codes and names are listed below, from Unicode's emoji-data.txt and ISO 3166.
No pictures are made: each phone draws an emoji with its own system font, and
leaves out one its font has no glyph for.

The file is one object, "groups": the eight groups in the order the
Stickers panel shows them, each {"name", "emoji": [...]}, and each emoji
{"g", "name", "keywords": [...], "tone"}:

  g         the fully-qualified emoji: one code point, with U+FE0F after one
            that is drawn as text unless asked (☀ is "☀️"), or a flag's two
            regional indicators. No sequence joined by U+200D is listed.
  name      its Unicode name in sentence case ("Grinning face"); a flag's is
            "Flag: " and its country.
  keywords  the name's words, lower case, without "with", "and", "of" and
            the like; a flag's also has its two-letter code.
  tone      whether it takes a skin tone (Emoji_Modifier_Base): the panel
            offers the five, U+1F3FB to U+1F3FF, put straight after it.

Each emoji goes in the group whose code points hold it (GROUPS, the first
range that does), in code point order; flags in country-code order.

After the groups, "pictographic": the Extended_Pictographic code points
(emoji-data.txt, Unicode 15) as [first, last] pairs, in order — the table
both phones' Emoji.isEmojiCluster reads, so a curve, a path or an outline
effect keeps a colour emoji its font has no outline for.
"""
import json
import pathlib
import sys
import unicodedata

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCE = REPO / 'core/src/main/resources/com/canvia/core/content/emoji.json'


def ranges(text):
    out = []
    for part in text.split():
        a, _, b = part.partition('..')
        out.append((int(a, 16), int(b or a, 16)))
    return out


def within(cp, spans):
    return any(a <= cp <= b for a, b in spans)


# Emoji_Presentation=Yes, singly (emoji-data.txt, Unicode 14), regional
# indicators and skin-tone modifiers aside: drawn as emoji as they are.
PRESENTATION = ranges('''
231A..231B 23E9..23EC 23F0 23F3 25FD..25FE 2614..2615 2648..2653 267F 2693
26A1 26AA..26AB 26BD..26BE 26C4..26C5 26CE 26D4 26EA 26F2..26F3 26F5 26FA
26FD 2705 270A..270B 2728 274C 274E 2753..2755 2757 2795..2797 27B0 27BF
2B1B..2B1C 2B50 2B55 1F004 1F0CF 1F18E 1F191..1F19A 1F201 1F21A 1F22F
1F232..1F236 1F238..1F23A 1F250..1F251 1F300..1F320 1F32D..1F335
1F337..1F37C 1F37E..1F393 1F3A0..1F3CA 1F3CF..1F3D3 1F3E0..1F3F0 1F3F4
1F3F8..1F3FA 1F400..1F43E 1F440 1F442..1F4FC 1F4FF..1F53D 1F54B..1F54E
1F550..1F567 1F57A 1F595..1F596 1F5A4 1F5FB..1F64F 1F680..1F6C5 1F6CC
1F6D0..1F6D2 1F6D5..1F6D7 1F6DD..1F6DF 1F6EB..1F6EC 1F6F4..1F6FC
1F7E0..1F7EB 1F7F0 1F90C..1F93A 1F93C..1F945 1F947..1F9FF 1FA70..1FA74
1FA78..1FA7C 1FA80..1FA86 1FA90..1FAAC 1FAB0..1FABA 1FAC0..1FAC5
1FAD0..1FAD9 1FAE0..1FAE7 1FAF0..1FAF6
''')

# Emoji drawn as text unless U+FE0F follows (Emoji=Yes,
# Emoji_Presentation=No), keycap bases aside: listed with U+FE0F.
TEXT_DEFAULT = ranges('''
00A9 00AE 203C 2049 2122 2139 2194..2199 21A9..21AA 2328 23CF 23ED..23EF
23F1..23F2 23F8..23FA 24C2 25AA..25AB 25B6 25C0 25FB..25FC 2600..2604 260E
2611 2618 261D 2620 2622..2623 2626 262A 262E..262F 2638..263A 2640 2642
265F..2660 2663 2665..2666 2668 267B 267E 2692 2694..2697 2699 269B..269C
26A0 26A7 26B0..26B1 26C8 26CF 26D1 26D3 26E9 26F0..26F1 26F4 26F7..26F9
2702 2708..2709 270C..270D 270F 2712 2714 2716 271D 2721 2733..2734 2744
2747 2763..2764 27A1 2934..2935 2B05..2B07 3030 303D 3297 3299 1F170..1F171
1F17E..1F17F 1F202 1F237 1F321 1F324..1F32C 1F336 1F37D 1F396..1F397
1F399..1F39B 1F39E..1F39F 1F3CB..1F3CE 1F3D4..1F3DF 1F3F3 1F3F5 1F3F7 1F43F
1F441 1F4FD 1F549..1F54A 1F56F..1F570 1F573..1F579 1F587 1F58A..1F58D 1F590
1F5A5 1F5A8 1F5B1..1F5B2 1F5BC 1F5C2..1F5C4 1F5D1..1F5D3 1F5DC..1F5DE 1F5E1
1F5E3 1F5E8 1F5EF 1F5F3 1F5FA 1F6CB 1F6CD..1F6CF 1F6E0..1F6E5 1F6E9 1F6F0
1F6F3
''')

# Emoji_Modifier_Base: those that take a skin tone.
TONE = ranges('''
261D 26F9 270A..270D 1F385 1F3C2..1F3C4 1F3C7 1F3CA..1F3CC 1F442..1F443
1F446..1F450 1F466..1F478 1F47C 1F481..1F483 1F485..1F487 1F48F 1F491 1F4AA
1F574..1F575 1F57A 1F590 1F595..1F596 1F645..1F647 1F64B..1F64F 1F6A3
1F6B4..1F6B6 1F6C0 1F6CC 1F90C 1F90F 1F918..1F91F 1F926 1F930..1F939
1F93C..1F93E 1F977 1F9B5..1F9B6 1F9B8..1F9B9 1F9BB 1F9CD..1F9CF 1F9D1..1F9DD
1FAC3..1FAC5 1FAF0..1FAF6
''')

# The groups, and the code points each holds; an emoji goes in the first
# that holds it, else Symbols. Flags are the regional pairs below and the
# few flags of one code point.
GROUPS = [
    ('Flags', ranges('1F3C1 1F38C 1F3F3 1F3F4 1F6A9')),
    ('Smileys & People', ranges('''
        1F600..1F64F 1F910..1F92F 1F970..1F97A 1F9D0..1F9DF 1F9B0..1F9B9 1F9BB
        1F9BE..1F9BF 1F9CC..1F9CF 1F9E0 1FAE0..1FAF6 1FAC0..1FAC5 1F440..1F450
        1F463..1F487 1F48B 1F48F 1F491 1F4A2..1F4A9 1F4AA..1F4AB 1F574..1F575
        1F57A 1F590 1F595..1F596 1F6B4..1F6B6 1F6C0 1F6CC 1F918..1F91F 1F926
        1F930..1F939 1F93C..1F93E 1F977 263A 2639 261D 270A..270D 2620 1F5E3
        1F90C..1F90F''')),
    ('Animals & Nature', ranges('''
        1F400..1F43F 1F980..1F9AE 1FAB0..1FABA 1F330..1F335 1F337..1F344 1F490
        1F300..1F320 1F321..1F32C 2600..2604 2614 26A1 26C4..26C5 26C8 2744
        1F54A 1F577..1F578 1F4AE 1F3F5 1F525 1F4A7 1FAB7..1FAB8''')),
    ('Food', ranges('''
        1F345..1F37F 1F950..1F96F 1F9C0..1F9CB 1FAD0..1FADB 1F32D..1F32F 1F336
        2615''')),
    ('Activities', ranges('''
        1F380..1F393 1F396..1F3CF 1F3D0..1F3D3 1F3F8..1F3F9 1F93A..1F94F
        26BD..26BE 26F3 26F8..26F9 1F6F7 1F6F9 1FA80..1FA86 1F9E7..1F9E9 1F9F5
        1F9F6 1F9F8 1F0CF 1F004 265F 2660..2666 1F3AF 1FA70..1FA74''')),
    ('Travel', ranges('''
        1F680..1F6C5 1F6CB..1F6FF 1F3D4..1F3F0 1F5FA..1F5FF 26E9..26FA 2693 2708
        23F0..23F3 1F550..1F567 1F9F3 1F30D..1F310''')),
    ('Objects', ranges('''
        1F4B0..1F4FF 1F507..1F514 1F526..1F52E 1F56F..1F573 1F576 1F579..1F5A5
        1F5A8..1F5F3 1F9F0..1F9FF 1FA78..1FA7C 1FA90..1FAAC 1F451..1F462
        1F48C..1F48E 1F4A1 1F4A3 260E 2702 2709 270F 2712 231A..231B 2328
        2692..2697 2699 26B0..26B1 26CF 26D1 26D3 1F4BA''')),
]

# Words left out of keywords.
STOP = {'with', 'and', 'of', 'the', 'a', 'an', 'in', 'on', 'for', 'or'}

# Flags: RGI country and region codes, and what each is called.
COUNTRIES = '''
AC Ascension Island|AD Andorra|AE United Arab Emirates|AF Afghanistan|AG Antigua and Barbuda|AI Anguilla|AL Albania|AM Armenia|AO Angola|AQ Antarctica|AR Argentina|AS American Samoa|AT Austria|AU Australia|AW Aruba|AX Aland Islands|AZ Azerbaijan|
BA Bosnia and Herzegovina|BB Barbados|BD Bangladesh|BE Belgium|BF Burkina Faso|BG Bulgaria|BH Bahrain|BI Burundi|BJ Benin|BL St. Barthelemy|BM Bermuda|BN Brunei|BO Bolivia|BQ Caribbean Netherlands|BR Brazil|BS Bahamas|BT Bhutan|BV Bouvet Island|BW Botswana|BY Belarus|BZ Belize|
CA Canada|CC Cocos Islands|CD Congo - Kinshasa|CF Central African Republic|CG Congo - Brazzaville|CH Switzerland|CI Cote d'Ivoire|CK Cook Islands|CL Chile|CM Cameroon|CN China|CO Colombia|CP Clipperton Island|CR Costa Rica|CU Cuba|CV Cape Verde|CW Curacao|CX Christmas Island|CY Cyprus|CZ Czechia|
DE Germany|DG Diego Garcia|DJ Djibouti|DK Denmark|DM Dominica|DO Dominican Republic|DZ Algeria|
EA Ceuta and Melilla|EC Ecuador|EE Estonia|EG Egypt|EH Western Sahara|ER Eritrea|ES Spain|ET Ethiopia|EU European Union|
FI Finland|FJ Fiji|FK Falkland Islands|FM Micronesia|FO Faroe Islands|FR France|
GA Gabon|GB United Kingdom|GD Grenada|GE Georgia|GF French Guiana|GG Guernsey|GH Ghana|GI Gibraltar|GL Greenland|GM Gambia|GN Guinea|GP Guadeloupe|GQ Equatorial Guinea|GR Greece|GS South Georgia and South Sandwich Islands|GT Guatemala|GU Guam|GW Guinea-Bissau|GY Guyana|
HK Hong Kong|HM Heard and McDonald Islands|HN Honduras|HR Croatia|HT Haiti|HU Hungary|
IC Canary Islands|ID Indonesia|IE Ireland|IL Israel|IM Isle of Man|IN India|IO British Indian Ocean Territory|IQ Iraq|IR Iran|IS Iceland|IT Italy|
JE Jersey|JM Jamaica|JO Jordan|JP Japan|
KE Kenya|KG Kyrgyzstan|KH Cambodia|KI Kiribati|KM Comoros|KN St. Kitts and Nevis|KP North Korea|KR South Korea|KW Kuwait|KY Cayman Islands|KZ Kazakhstan|
LA Laos|LB Lebanon|LC St. Lucia|LI Liechtenstein|LK Sri Lanka|LR Liberia|LS Lesotho|LT Lithuania|LU Luxembourg|LV Latvia|LY Libya|
MA Morocco|MC Monaco|MD Moldova|ME Montenegro|MF St. Martin|MG Madagascar|MH Marshall Islands|MK North Macedonia|ML Mali|MM Myanmar|MN Mongolia|MO Macao|MP Northern Mariana Islands|MQ Martinique|MR Mauritania|MS Montserrat|MT Malta|MU Mauritius|MV Maldives|MW Malawi|MX Mexico|MY Malaysia|MZ Mozambique|
NA Namibia|NC New Caledonia|NE Niger|NF Norfolk Island|NG Nigeria|NI Nicaragua|NL Netherlands|NO Norway|NP Nepal|NR Nauru|NU Niue|NZ New Zealand|
OM Oman|
PA Panama|PE Peru|PF French Polynesia|PG Papua New Guinea|PH Philippines|PK Pakistan|PL Poland|PM St. Pierre and Miquelon|PN Pitcairn Islands|PR Puerto Rico|PS Palestinian Territories|PT Portugal|PW Palau|PY Paraguay|
QA Qatar|
RE Reunion|RO Romania|RS Serbia|RU Russia|RW Rwanda|
SA Saudi Arabia|SB Solomon Islands|SC Seychelles|SD Sudan|SE Sweden|SG Singapore|SH St. Helena|SI Slovenia|SJ Svalbard and Jan Mayen|SK Slovakia|SL Sierra Leone|SM San Marino|SN Senegal|SO Somalia|SR Suriname|SS South Sudan|ST Sao Tome and Principe|SV El Salvador|SX Sint Maarten|SY Syria|SZ Eswatini|
TA Tristan da Cunha|TC Turks and Caicos Islands|TD Chad|TF French Southern Territories|TG Togo|TH Thailand|TJ Tajikistan|TK Tokelau|TL Timor-Leste|TM Turkmenistan|TN Tunisia|TO Tonga|TR Turkey|TT Trinidad and Tobago|TV Tuvalu|TW Taiwan|TZ Tanzania|
UA Ukraine|UG Uganda|UM U.S. Outlying Islands|UN United Nations|US United States|UY Uruguay|UZ Uzbekistan|
VA Vatican City|VC St. Vincent and Grenadines|VE Venezuela|VG British Virgin Islands|VI U.S. Virgin Islands|VN Vietnam|VU Vanuatu|
WF Wallis and Futuna|WS Samoa|
XK Kosovo|
YE Yemen|YT Mayotte|
ZA South Africa|ZM Zambia|ZW Zimbabwe
'''

# Extended_Pictographic=Yes (emoji-data.txt, Unicode 15): what an emoji
# cluster starts from, sequences aside.
PICTOGRAPHIC = ranges('''
00A9 00AE 203C 2049 2122 2139 2194..2199 21A9..21AA 231A..231B 2328 2388
23CF 23E9..23F3 23F8..23FA 24C2 25AA..25AB 25B6 25C0 25FB..25FE 2600..2605
2607..2612 2614..2685 2690..2705 2708..2712 2714 2716 271D 2721 2728
2733..2734 2744 2747 274C 274E 2753..2755 2757 2763..2767 2795..2797 27A1
27B0 27BF 2934..2935 2B05..2B07 2B1B..2B1C 2B50 2B55 3030 303D 3297 3299
1F000..1F0FF 1F10D..1F10F 1F12F 1F16C..1F171 1F17E..1F17F 1F18E
1F191..1F19A 1F1AD..1F1E5 1F201..1F20F 1F21A 1F22F 1F232..1F23A
1F23C..1F23F 1F249..1F3FA 1F400..1F53D 1F546..1F64F 1F680..1F6FF
1F774..1F77F 1F7D5..1F7FF 1F80C..1F80F 1F848..1F84F 1F85A..1F85F
1F888..1F88F 1F8AE..1F8FF 1F90C..1F93A 1F93C..1F945 1F947..1FAFF
1FC00..1FFFD
''')

ORDER = ['Smileys & People', 'Animals & Nature', 'Food', 'Activities', 'Travel', 'Objects', 'Symbols', 'Flags']


def sentence(name):
    text = name.lower()
    return text[:1].upper() + text[1:]


def keywords(name, extra=()):
    words = []
    for w in name.lower().replace('-', ' ').replace(':', ' ').replace(',', ' ').split():
        w = w.strip('.()\'')
        if w and w not in STOP and w not in words:
            words.append(w)
    for w in extra:
        if w not in words:
            words.append(w)
    return words


def group_of(cp):
    for name, spans in GROUPS:
        if within(cp, spans):
            return name
    return 'Symbols'


def build():
    groups = {name: [] for name in ORDER}
    seen = set()
    for spans, qualify in ((PRESENTATION, False), (TEXT_DEFAULT, True)):
        for a, b in spans:
            for cp in range(a, b + 1):
                if cp in seen or 0x1F3FB <= cp <= 0x1F3FF or 0x1F1E6 <= cp <= 0x1F1FF:
                    continue
                try:
                    name = unicodedata.name(chr(cp))
                except ValueError:
                    continue   # not in this Python's Unicode
                seen.add(cp)
                groups[group_of(cp)].append((cp, {
                    'g': chr(cp) + ('️' if qualify else ''),
                    'name': sentence(name),
                    'keywords': keywords(name),
                    'tone': within(cp, TONE),
                }))
    for g in groups.values():
        g.sort(key=lambda item: item[0])
    flags = []
    for entry in COUNTRIES.replace('\n', '').split('|'):
        code, _, country = entry.strip().partition(' ')
        glyph = ''.join(chr(0x1F1E6 + ord(c) - ord('A')) for c in code)
        flags.append((code, {
            'g': glyph,
            'name': 'Flag: ' + country,
            'keywords': keywords('flag ' + country, [code.lower()]),
            'tone': False,
        }))
    flags.sort(key=lambda item: item[0])
    groups['Flags'] = groups['Flags'] + flags
    return [{'name': name, 'emoji': [e for _, e in groups[name]]} for name in ORDER]


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    groups = build()
    lines = []
    for i, group in enumerate(groups):
        body = ',\n'.join(json.dumps(e, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for e in group['emoji'])
        lines.append('{"emoji":[\n' + body + '\n],"name":' + json.dumps(group['name'], ensure_ascii=False) + '}')
    pictographic = json.dumps([[a, b] for a, b in PICTOGRAPHIC], separators=(',', ':'))
    text = '{"groups":[\n' + ',\n'.join(lines) + '\n],\n"pictographic":' + pictographic + '}\n'
    RESOURCE.write_text(text, encoding='utf-8')
    total = sum(len(g['emoji']) for g in groups)
    print('%d emoji in %d groups (%s)' % (total, len(groups), ', '.join('%s %d' % (g['name'], len(g['emoji'])) for g in groups)))
    if len(sys.argv) == 2:
        out = pathlib.Path(sys.argv[1]) / 'emoji.json'
        out.write_text(text, encoding='utf-8')
        print('and', out)


if __name__ == '__main__':
    main()
