#!/usr/bin/env node
// Static verification for the Canvia iOS sources — a partial stand-in for a
// compiler when Xcode isn't available. Uses the real tree-sitter Swift
// grammar, so it sees the same syntax the compiler does.
//
//   npm install            # tree-sitter + tree-sitter-swift
//   node verify.js ../Canvia ../Tests
//
// Checks, in order:
//   1. every file parses (no ERROR/MISSING nodes)
//   2. every call into project code matches a declared signature's argument
//      labels, accounting for defaulted parameters
//   3. every implicit-member argument (.case) names a real case of the
//      parameter's enum type
//   4. every switch over a project enum is exhaustive or has a default
//
// It does NOT type-check. A clean run means the syntax and the project's
// internal API surface are consistent; it cannot prove the app builds.

const Parser = require('tree-sitter');
const Swift = require('tree-sitter-swift');
const fs = require('fs');
const path = require('path');
const parser = new Parser();
parser.setLanguage(Swift);

const ROOTS = process.argv.slice(2);
if (!ROOTS.length) { console.error('usage: node verify.js <dir...>'); process.exit(2); }

const collect = (dir, acc = []) => {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) collect(p, acc);
    else if (e.name.endsWith('.swift')) acc.push(p);
  }
  return acc;
};
let FILES = [];
for (const r of ROOTS) FILES = FILES.concat(fs.statSync(r).isDirectory() ? collect(r) : [r]);
FILES.sort();
const each = (n, f) => { f(n); for (let i = 0; i < n.namedChildCount; i++) each(n.namedChild(i), f); };
const rel = f => path.relative(process.cwd(), f);
let FAILURES = 0;

// ---------------------------------------------------------------- 1. parse
console.log('\n[1/4] parsing');
for (const f of FILES) {
  const tree = parser.parse(fs.readFileSync(f, 'utf8'));
  const problems = [];
  each(tree.rootNode, n => {
    if (n.type === 'ERROR') problems.push(`ERROR at ${n.startPosition.row + 1}:${n.startPosition.column + 1}`);
    else if (n.isMissing) problems.push(`MISSING ${n.type} at ${n.startPosition.row + 1}`);
  });
  if (problems.length) { FAILURES += problems.length; console.log(`  FAIL ${rel(f)}: ${problems.slice(0,4).join('; ')}`); }
}
console.log(`      ${FILES.length} files`);

// ------------------------------------------------- 2. argument labels
console.log('[2/4] argument labels');
const decls = new Map(), ourTypes = new Set();
for (const f of FILES) {
  const tree = parser.parse(fs.readFileSync(f, 'utf8'));
  each(tree.rootNode, n => {
    if (n.type === 'class_declaration' || n.type === 'protocol_declaration') {
      const id = n.namedChildren.find(c => c.type === 'type_identifier');
      if (id) ourTypes.add(id.text);
    }
    if (n.type !== 'function_declaration' && n.type !== 'init_declaration') return;
    let name = 'init';
    if (n.type === 'function_declaration') {
      const id = n.namedChildren.find(c => c.type === 'simple_identifier');
      if (!id) return; name = id.text;
    }
    const labels = [];
    const kids = n.namedChildren;
    kids.filter(c => c.type === 'parameter').forEach(p => {
      const ids = p.namedChildren.filter(c => c.type === 'simple_identifier');
      const label = ids.length >= 2 ? ids[0].text : (ids[0] ? ids[0].text : '_');
      let hasDefault = !!p.namedChildren.find(c => c.type === 'default_value') || /=\s*\S/.test(p.text);
      if (!hasDefault) {
        const nxt = kids[kids.indexOf(p) + 1];
        if (nxt && !['parameter','function_body','user_type','type_annotation','modifiers',
                     'type_constraints','optional_type','array_type','dictionary_type',
                     'function_type','tuple_type'].includes(nxt.type)) hasDefault = true;
      }
      labels.push({ label, hasDefault });
    });
    if (!decls.has(name)) decls.set(name, []);
    decls.get(name).push({ labels, file: f, row: n.startPosition.row + 1 });
  });
}
const OUR_BASES = new Set([...ourTypes, 'Geometry','Element','Design','Page','Paint','SVGPath','UID',
  'ContentLibrary','FontLibrary','PhotoLibrary','DesignLibrary','MediaStore','ImageFilterEngine',
  'TextEffect','ColorTools','TemplateThumbCache','Self','store','s','ImageFilterPreset','SizePreset']);
const argLabels = suffix => {
  const va = suffix.namedChildren.find(c => c.type === 'value_arguments');
  const out = [];
  if (va) for (const a of va.namedChildren.filter(c => c.type === 'value_argument')) {
    const lbl = a.namedChildren.find(c => c.type === 'value_argument_label');
    out.push(lbl ? (lbl.namedChildren[0] ? lbl.namedChildren[0].text : lbl.text) : '_');
  }
  if (suffix.namedChildren.find(c => c.type === 'lambda_literal')) out.push('_TRAILING_');
  return out;
};
const matches = (sig, given) => {
  let i = 0;
  for (const g of given) {
    let advanced = false;
    while (i < sig.length) {
      if (sig[i].label === g || g === '_TRAILING_') { i++; advanced = true; break; }
      if (sig[i].hasDefault) { i++; continue; }
      return false;
    }
    if (!advanced) return false;
  }
  while (i < sig.length) { if (!sig[i].hasDefault) return false; i++; }
  return true;
};
let calls = 0;
for (const f of FILES) {
  const tree = parser.parse(fs.readFileSync(f, 'utf8'));
  each(tree.rootNode, n => {
    if (n.type !== 'call_expression') return;
    const callee = n.namedChild(0), suffix = n.namedChildren.find(c => c.type === 'call_suffix');
    if (!callee || !suffix || callee.type !== 'navigation_expression') return;
    const b = callee.namedChild(0), suf = callee.namedChildren.find(c => c.type === 'navigation_suffix');
    if (!suf) return;
    const id = suf.namedChildren.find(c => c.type === 'simple_identifier');
    if (!id) return;
    const base = b && b.type === 'simple_identifier' ? b.text : null;
    if (!base || !OUR_BASES.has(base) || !decls.has(id.text)) return;
    calls++;
    const given = argLabels(suffix);
    if (decls.get(id.text).some(d => matches(d.labels, given))) return;
    FAILURES++;
    console.log(`  FAIL ${rel(f)}:${n.startPosition.row + 1}  ${base}.${id.text}(${given.join(', ')})`);
    for (const d of decls.get(id.text))
      console.log(`         declared: ${id.text}(${d.labels.map(l => l.label + (l.hasDefault ? '=' : '')).join(', ')})`);
  });
}
console.log(`      ${calls} internal calls`);

// --------------------------------------- 3 & 4. enum cases + exhaustiveness
console.log('[3/4] enum-case arguments');
const enums = new Map();
for (const f of FILES) {
  const tree = parser.parse(fs.readFileSync(f, 'utf8'));
  each(tree.rootNode, n => {
    if (n.type !== 'class_declaration') return;
    if (!/^\s*(public |private |internal |fileprivate )?(indirect )?enum\b/.test(n.text)) return;
    const id = n.namedChildren.find(c => c.type === 'type_identifier'); if (!id) return;
    const cases = new Set();
    (function own(node, depth) {
      for (const m of node.namedChildren) {
        if (depth > 0 && m.type === 'class_declaration' &&
            /^\s*(public |private |internal |fileprivate )?(indirect )?enum\b/.test(m.text)) continue;
        if (m.type === 'enum_entry')
          for (const c of m.namedChildren.filter(c => c.type === 'simple_identifier')) cases.add(c.text);
        own(m, depth + 1);
      }
    })(n, 0);
    if (cases.size) enums.set(id.text, cases);
  });
}
const paramEnum = new Map();
for (const f of FILES) {
  const tree = parser.parse(fs.readFileSync(f, 'utf8'));
  each(tree.rootNode, n => {
    if (n.type !== 'function_declaration') return;
    const id = n.namedChildren.find(c => c.type === 'simple_identifier'); if (!id) return;
    n.namedChildren.filter(c => c.type === 'parameter').forEach((p, i) => {
      const t = p.namedChildren.find(c => c.type === 'user_type');
      const tn = t && t.namedChildren.find(c => c.type === 'type_identifier');
      if (tn && enums.has(tn.text)) paramEnum.set(`${id.text}#${i}`, tn.text);
    });
  });
}
let caseArgs = 0;
for (const f of FILES) {
  const tree = parser.parse(fs.readFileSync(f, 'utf8'));
  each(tree.rootNode, n => {
    if (n.type !== 'call_expression') return;
    const callee = n.namedChild(0), suffix = n.namedChildren.find(c => c.type === 'call_suffix');
    if (!callee || !suffix) return;
    let name = null;
    if (callee.type === 'navigation_expression') {
      const s = callee.namedChildren.find(c => c.type === 'navigation_suffix');
      const i = s && s.namedChildren.find(c => c.type === 'simple_identifier'); if (i) name = i.text;
    } else if (callee.type === 'simple_identifier') name = callee.text;
    if (!name) return;
    const va = suffix.namedChildren.find(c => c.type === 'value_arguments'); if (!va) return;
    va.namedChildren.filter(c => c.type === 'value_argument').forEach((a, i) => {
      const en = paramEnum.get(`${name}#${i}`); if (!en) return;
      const pre = a.namedChildren.find(c => c.type === 'prefix_expression'); if (!pre) return;
      const cid = pre.namedChildren.find(c => c.type === 'simple_identifier'); if (!cid) return;
      caseArgs++;
      if (!enums.get(en).has(cid.text)) {
        FAILURES++;
        console.log(`  FAIL ${rel(f)}:${a.startPosition.row + 1}  ${name} arg ${i} = .${cid.text}; ${en} has {${[...enums.get(en)].join(', ')}}`);
      }
    });
  });
}
console.log(`      ${caseArgs} enum-case arguments`);

console.log('[4/4] switch exhaustiveness');
let switches = 0;
for (const f of FILES) {
  const tree = parser.parse(fs.readFileSync(f, 'utf8'));
  each(tree.rootNode, n => {
    if (n.type !== 'switch_statement') return;
    const entries = n.namedChildren.filter(c => c.type === 'switch_entry');
    if (entries.some(e => /^\s*default\s*:/.test(e.text))) return;
    const used = new Set();
    for (const e of entries) for (const m of e.text.matchAll(/(?:^|[\s,(])\.([A-Za-z_]\w*)/g)) used.add(m[1]);
    if (!used.size) return;
    let best = null;
    for (const [en, cs] of enums) {
      const covered = [...used].filter(u => cs.has(u)).length;
      if (covered && covered === used.size && (!best || cs.size < best[1].size)) best = [en, cs];
    }
    if (!best) return;
    switches++;
    const missing = [...best[1]].filter(c => !used.has(c));
    if (missing.length) {
      FAILURES++;
      console.log(`  FAIL ${rel(f)}:${n.startPosition.row + 1}  switch over ${best[0]} missing {${missing.join(', ')}}, no default`);
    }
  });
}
console.log(`      ${switches} switches over project enums`);

console.log(FAILURES === 0 ? '\nOK — no static problems found\n' : `\n${FAILURES} PROBLEM(S)\n`);
process.exit(FAILURES === 0 ? 0 : 1);
