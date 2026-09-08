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
//   5. no ViewBuilder block exceeds SwiftUI's ten-child limit
//   6. no closure passed to a higher-order stdlib method silently ignores
//      the argument it is required to take
//   7. every argument in an inout position is passed with an explicit &
//   8. no synchronous, non-isolated function calls a @MainActor one directly
//   9. no file-scope `private` declaration is referenced from another file
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
// tree-sitter's Node binding copies string input into a fixed buffer and
// throws "Invalid argument" past about 32 KB. The callback form has no such
// limit, so anything large is fed through it — a source file crossing that
// size must not silently stop being checked.
const parse = src => src.length < 30000
  ? parser.parse(src)
  : parser.parse(index => src.slice(index, index + 4096));
const each = (n, f) => { f(n); for (let i = 0; i < n.namedChildCount; i++) each(n.namedChild(i), f); };
const rel = f => path.relative(process.cwd(), f);
let FAILURES = 0;

// ---------------------------------------------------------------- 1. parse
console.log('\n[1/9] parsing');
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
  const problems = [];
  each(tree.rootNode, n => {
    if (n.type === 'ERROR') problems.push(`ERROR at ${n.startPosition.row + 1}:${n.startPosition.column + 1}`);
    else if (n.isMissing) problems.push(`MISSING ${n.type} at ${n.startPosition.row + 1}`);
  });
  if (problems.length) { FAILURES += problems.length; console.log(`  FAIL ${rel(f)}: ${problems.slice(0,4).join('; ')}`); }
}
console.log(`      ${FILES.length} files`);

// ------------------------------------------------- 2. argument labels
console.log('[2/9] argument labels');
const decls = new Map(), ourTypes = new Set();
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
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
      // `inout` only as a parameter modifier — a closure-typed parameter
      // like `(inout Design) -> Void` has "inout" in its text but is passed
      // by value like anything else.
      const mods = p.namedChildren.find(c => c.type === 'parameter_modifiers');
      const isInout = !!(mods && /\binout\b/.test(mods.text));
      labels.push({ label, hasDefault, isInout });
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
  const tree = parse(fs.readFileSync(f, 'utf8'));
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
console.log('[3/9] enum-case arguments');
const enums = new Map();
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
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
  const tree = parse(fs.readFileSync(f, 'utf8'));
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
  const tree = parse(fs.readFileSync(f, 'utf8'));
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

console.log('[4/9] switch exhaustiveness');
let switches = 0;
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
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


// ------------------------------------------- 5. ViewBuilder child limits
// A ViewBuilder block accepts at most ten child views; exceeding it fails
// with an opaque type-inference error rather than a clear diagnostic.
console.log('[5/9] ViewBuilder child counts');
const CONTAINERS = new Set(['HStack','VStack','ZStack','Group','Form','List','Section','Menu',
  'ScrollView','NavigationStack','LazyVStack','LazyHStack','LazyVGrid','LazyHGrid','ToolbarItemGroup']);
const countViews = stmts => stmts.namedChildren.filter(c =>
  c.type !== 'property_declaration' && c.type !== 'assignment' && c.type !== 'comment').length;
let builders = 0;
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
  each(tree.rootNode, n => {
    let stmts = null, what = null;
    if ((n.type === 'function_declaration' || n.type === 'property_declaration')
        && /@ViewBuilder/.test(n.text.slice(0, 200))) {
      const body = n.namedChildren.find(c => c.type === 'function_body'
                                          || c.type === 'computed_property');
      stmts = body && body.namedChildren.find(c => c.type === 'statements');
      what = '@ViewBuilder block';
    } else if (n.type === 'call_expression') {
      const callee = n.namedChild(0);
      if (callee && callee.type === 'simple_identifier' && CONTAINERS.has(callee.text)) {
        const suffix = n.namedChildren.find(c => c.type === 'call_suffix');
        const lambda = suffix && suffix.namedChildren.find(c => c.type === 'lambda_literal');
        stmts = lambda && lambda.namedChildren.find(c => c.type === 'statements');
        what = `${callee.text} { }`;
      }
    }
    if (!stmts) return;
    builders++;
    const count = countViews(stmts);
    if (count > 10) {
      FAILURES++;
      console.log(`  FAIL ${rel(f)}:${n.startPosition.row + 1}  ${what} has ${count} children (limit 10)`);
    }
  });
}
console.log(`      ${builders} ViewBuilder blocks`);


// ------------------------- 6. closures that ignore a required argument
// `xs.filter { flag }` is a hard error ("contextual type for closure argument
// list expects 1 argument, which cannot be implicitly ignored") — and usually
// signals a predicate that forgot to look at the element. A shorthand closure
// passed to one of these methods must reference the arguments it is given.
console.log('[6/9] closure arguments');
const HOF = new Map([
  ['filter', 1], ['map', 1], ['compactMap', 1], ['flatMap', 1], ['forEach', 1],
  ['first', 1], ['firstIndex', 1], ['last', 1], ['lastIndex', 1],
  ['contains', 1], ['allSatisfy', 1], ['drop', 1], ['prefix', 1],
  ['removeAll', 1], ['partition', 1], ['split', 1],
  ['sorted', 2], ['min', 2], ['max', 2], ['reduce', 2],
]);
// $0 inside a nested closure belongs to that closure, not this one.
const shorthandArgs = lambda => {
  const found = new Set();
  const walk = (n, top) => {
    if (!top && n.type === 'lambda_literal') return;
    if (n.type === 'simple_identifier' && /^\$\d+$/.test(n.text)) found.add(n.text);
    for (let i = 0; i < n.namedChildCount; i++) walk(n.namedChild(i), false);
  };
  walk(lambda, true);
  return found;
};
let closures = 0;
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
  each(tree.rootNode, n => {
    if (n.type !== 'call_expression') return;
    const callee = n.namedChild(0);
    if (!callee || callee.type !== 'navigation_expression') return;
    const suffix = callee.namedChildren.find(c => c.type === 'navigation_suffix');
    const method = suffix && suffix.namedChildren.find(c => c.type === 'simple_identifier');
    if (!method || !HOF.has(method.text)) return;

    const call = n.namedChildren.find(c => c.type === 'call_suffix');
    if (!call) return;
    // Trailing closure, or one passed as a labelled argument (where:/by:).
    let lambda = call.namedChildren.find(c => c.type === 'lambda_literal');
    if (!lambda) {
      const args = call.namedChildren.find(c => c.type === 'value_arguments');
      for (const a of args ? args.namedChildren : []) {
        const l = a.namedChildren.find(c => c.type === 'lambda_literal');
        if (l) lambda = l;
      }
    }
    if (!lambda) return;
    // An explicit parameter list (including `_ in`) is always fine.
    if (lambda.namedChildren.some(c => c.type === 'lambda_function_type')) return;

    closures++;
    const arity = HOF.get(method.text);
    const used = shorthandArgs(lambda);
    const missing = [];
    for (let i = 0; i < arity; i++) if (!used.has(`$${i}`)) missing.push(`$${i}`);
    // A one-argument closure that uses none of its arguments is the error the
    // compiler rejects; for the two-argument forms, `$0` alone still compiles
    // (`$1` is inferred as unused), so only flag using neither.
    const broken = arity === 1 ? missing.length === 1 : used.size === 0;
    if (broken) {
      FAILURES++;
      console.log(`  FAIL ${rel(f)}:${lambda.startPosition.row + 1}  .${method.text} { } ignores ${missing.join(', ')}`);
    }
  });
}
console.log(`      ${closures} shorthand closures`);

// ------------------------------------------------------- 7. inout arguments
// Swift needs `&` at the call site for an inout parameter, and forgetting it
// is a plain compile error that costs a full macOS CI leg to discover. The
// grammar makes it cheap to catch here: a parameter carries `inout` as a
// modifier node, which a closure-typed parameter such as `(inout Design) ->
// Void` does not.
console.log('[7/9] inout arguments');
const requiredAmps = new Map();
for (const [name, ds] of decls) {
  // The minimum across overloads: if any declaration of this name takes no
  // inout parameter, a call with no `&` may well be that one.
  const counts = ds.map(d => d.labels.filter(l => l.isInout && !l.hasDefault).length);
  const need = counts.length ? Math.min(...counts) : 0;
  if (need > 0) requiredAmps.set(name, need);
}
let inoutCalls = 0;
if (requiredAmps.size) {
  for (const f of FILES) {
    const tree = parse(fs.readFileSync(f, 'utf8'));
    each(tree.rootNode, n => {
      if (n.type !== 'call_expression') return;
      const callee = n.namedChild(0);
      const suffix = n.namedChildren.find(c => c.type === 'call_suffix');
      if (!callee || !suffix) return;
      let name = null;
      if (callee.type === 'simple_identifier') name = callee.text;
      else if (callee.type === 'navigation_expression') {
        const suf = callee.namedChildren.find(c => c.type === 'navigation_suffix');
        const id = suf && suf.namedChildren.find(c => c.type === 'simple_identifier');
        if (id) name = id.text;
      }
      if (!name || !requiredAmps.has(name)) return;
      inoutCalls++;
      const va = suffix.namedChildren.find(c => c.type === 'value_arguments');
      const args = va ? va.namedChildren.filter(c => c.type === 'value_argument') : [];
      // The node's text carries the label too ("defs: &defs"), so strip a
      // leading label before looking for the ampersand.
      const value = a => a.text.replace(/^\s*[A-Za-z_][A-Za-z0-9_]*\s*:\s*/, '').trim();
      const amps = args.filter(a => value(a).startsWith('&')).length;
      const need = requiredAmps.get(name);
      if (amps >= need) return;
      FAILURES++;
      console.log(`  FAIL ${rel(f)}:${n.startPosition.row + 1}  ${name}(...) passes ${amps} `
        + `inout argument(s) but ${need} parameter(s) need an explicit &`);
    });
  }
}
console.log(`      ${inoutCalls} calls to ${requiredAmps.size} inout function(s)`);

// ------------------------------------------------- 8. main-actor isolation
// Calling a @MainActor function from a synchronous non-isolated one is a
// compile error, and the usual way to write it is a test method that forgot
// the attribute its helper has. Approximated rather than type-checked: a name
// counts as main-actor only if EVERY declaration of it is, and only direct
// calls in a function's own body are examined — a call inside a closure may
// well be inside a `Task { @MainActor in ... }`.
console.log('[8/9] main-actor isolation');
const MAIN_ACTOR_PROTOCOLS = new Set([
  'View', 'App', 'Scene', 'Shape', 'ViewModifier', 'ButtonStyle', 'PrimitiveButtonStyle',
  'UIViewRepresentable', 'UIViewControllerRepresentable', 'InsettableShape',
  'UIApplicationDelegate', 'UISceneDelegate',
]);
const isolatedNames = new Map();   // name -> {total, isolated}
const declaringNode = new Map();
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
  // A declaration is isolated if it carries @MainActor, or its enclosing type
  // does. tree-sitter exposes the attribute as an `attribute` child of the
  // declaration's `modifiers`.
  const isolatedType = node => {
    const mods = node.namedChildren.find(c => c.type === 'modifiers');
    if (mods && /@MainActor/.test(mods.text)) return true;
    // Conforming to one of these puts every member on the main actor without
    // an attribute anywhere in this source — the protocols themselves are
    // declared @MainActor in the SDK.
    return node.namedChildren
      .filter(c => c.type === 'inheritance_specifier')
      .some(c => MAIN_ACTOR_PROTOCOLS.has(c.text.trim()));
  };
  const walk = (node, inherited) => {
    let carries = inherited;
    if (node.type === 'class_declaration' || node.type === 'protocol_declaration') {
      carries = inherited || isolatedType(node);
    }
    if (node.type === 'function_declaration') {
      const id = node.namedChildren.find(c => c.type === 'simple_identifier');
      if (id) {
        const own = carries || isolatedType(node);
        const seen = isolatedNames.get(id.text) || { total: 0, isolated: 0 };
        seen.total++;
        if (own) seen.isolated++;
        isolatedNames.set(id.text, seen);
        declaringNode.set(id.text, rel(f) + ':' + (node.startPosition.row + 1));
      }
    }
    for (let i = 0; i < node.namedChildCount; i++) walk(node.namedChild(i), carries);
  };
  walk(tree.rootNode, false);
}
const mainActorOnly = new Set(
  [...isolatedNames].filter(([, v]) => v.total > 0 && v.total === v.isolated).map(([k]) => k));

let isolationChecks = 0;
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
  const typeIsolated = node => {
    const mods = node.namedChildren.find(c => c.type === 'modifiers');
    if (mods && /@MainActor/.test(mods.text)) return true;
    return node.namedChildren
      .filter(c => c.type === 'inheritance_specifier')
      .some(c => MAIN_ACTOR_PROTOCOLS.has(c.text.trim()));
  };
  const walk = (node, inherited) => {
    let carries = inherited;
    if (node.type === 'class_declaration' || node.type === 'protocol_declaration') {
      carries = inherited || typeIsolated(node);
    }
    if (node.type === 'function_declaration') {
      const id = node.namedChildren.find(c => c.type === 'simple_identifier');
      const mods = node.namedChildren.find(c => c.type === 'modifiers');
      const own = carries || !!(mods && /@MainActor/.test(mods.text));
      // async and throws-async bodies can await their way onto the actor.
      const isAsync = /\basync\b/.test(node.text.slice(0, node.text.indexOf('{') + 1));
      if (id && !own && !isAsync) {
        isolationChecks++;
        const body = node.namedChildren.find(c => c.type === 'function_body');
        if (body) {
          const offenders = [];
          const scan = n => {
            // Not into closures: a call there may sit inside Task { @MainActor in }.
            // Not into #selector either — naming a method is not calling it.
            if (n.type === 'lambda_literal' || n.type === 'selector_expression') return;
            if (n.type === 'call_expression') {
              const callee = n.namedChild(0);
              const suffix = n.namedChildren.find(c => c.type === 'call_suffix');
              // Subscripts parse as calls too — `body[a..<b]` is not a call to
              // anything named body — so require an actual parenthesised
              // argument list.
              if (!suffix || !suffix.text.trimStart().startsWith('(')) {
                for (let i = 0; i < n.namedChildCount; i++) scan(n.namedChild(i));
                return;
              }
              let name = null;
              if (callee && callee.type === 'simple_identifier') name = callee.text;
              else if (callee && callee.type === 'navigation_expression') {
                const suf = callee.namedChildren.find(c => c.type === 'navigation_suffix');
                const sid = suf && suf.namedChildren.find(c => c.type === 'simple_identifier');
                if (sid) name = sid.text;
              }
              if (name && mainActorOnly.has(name) && name !== id.text) {
                offenders.push({ name, row: n.startPosition.row + 1 });
              }
            }
            for (let i = 0; i < n.namedChildCount; i++) scan(n.namedChild(i));
          };
          scan(body);
          for (const o of offenders) {
            FAILURES++;
            console.log(`  FAIL ${rel(f)}:${o.row}  ${id.text} is not @MainActor but calls `
              + `${o.name} (declared @MainActor at ${declaringNode.get(o.name)})`);
          }
        }
      }
    }
    for (let i = 0; i < node.namedChildCount; i++) walk(node.namedChild(i), carries);
  };
  walk(tree.rootNode, false);
}
console.log(`      ${isolationChecks} non-isolated functions, ${mainActorOnly.size} main-actor names`);

// ------------------------------------------------ 9. file-scope private use
// `private` at file scope means this file only, which is easy to forget when
// a file is split in two — the symbol is still right there in the editor.
console.log('[9/9] file-scope private');
const privateAtFileScope = new Map();   // name -> file that declares it
const declaredAnywhere = new Map();     // file -> Set of names it declares
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
  const mine = new Set();
  each(tree.rootNode, n => {
    if (n.type === 'function_declaration' || n.type === 'class_declaration'
        || n.type === 'protocol_declaration' || n.type === 'typealias_declaration') {
      const id = n.namedChildren.find(c => c.type === 'simple_identifier'
        || c.type === 'type_identifier');
      if (id) mine.add(id.text);
    }
    if (n.type === 'property_declaration') {
      // The declared name only. Walking the whole declaration would sweep up
      // every identifier in the initialiser — including, for a computed `var
      // body`, the entire view — and then the guard below would treat this
      // file as declaring everything it merely mentions.
      const pattern = n.namedChildren.find(c => c.type === 'pattern');
      const id = pattern && pattern.namedChildren.find(c => c.type === 'simple_identifier');
      if (id) mine.add(id.text);
    }
  });
  declaredAnywhere.set(f, mine);

  // Only direct children of the file count: `private` inside a type is a
  // different rule and none of this applies to it.
  const root = tree.rootNode;
  for (let i = 0; i < root.namedChildCount; i++) {
    const n = root.namedChild(i);
    const mods = n.namedChildren.find(c => c.type === 'modifiers');
    if (!mods || !/\b(private|fileprivate)\b/.test(mods.text)) continue;
    let name = null;
    if (n.type === 'property_declaration') {
      const pattern = n.namedChildren.find(c => c.type === 'pattern');
      const id = pattern && pattern.namedChildren.find(c => c.type === 'simple_identifier');
      if (id) name = id.text;
    } else {
      const id = n.namedChildren.find(c => c.type === 'simple_identifier'
        || c.type === 'type_identifier');
      if (id) name = id.text;
    }
    if (name) privateAtFileScope.set(name, f);
  }
}
let privateRefs = 0;
for (const f of FILES) {
  const tree = parse(fs.readFileSync(f, 'utf8'));
  const reported = new Set();
  each(tree.rootNode, n => {
    if (n.type !== 'simple_identifier' && n.type !== 'type_identifier') return;
    const owner = privateAtFileScope.get(n.text);
    if (!owner || owner === f || reported.has(n.text)) return;
    // A file that declares the same name itself is talking about its own.
    if ((declaredAnywhere.get(f) || new Set()).has(n.text)) return;
    reported.add(n.text);
    FAILURES++;
    privateRefs++;
    console.log(`  FAIL ${rel(f)}:${n.startPosition.row + 1}  ${n.text} is private to `
      + `${rel(owner)} and cannot be seen from here`);
  });
}
console.log(`      ${privateAtFileScope.size} file-scope private names, ${privateRefs} escaped`);

console.log(FAILURES === 0 ? '\nOK — no static problems found\n' : `\n${FAILURES} PROBLEM(S)\n`);
process.exit(FAILURES === 0 ? 0 : 1);
