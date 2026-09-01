# Tools

`verify.js` runs static checks over the Swift sources using the real
tree-sitter Swift grammar. It is a partial stand-in for a compiler when
Xcode isn't available — useful on Linux/CI, or as a fast pre-commit gate.

```bash
cd Canvia/Tools
npm install
npm run verify
```

It checks that:

1. every file **parses** — no syntax errors;
2. every call into project code **matches a declared signature's argument
   labels**, accounting for defaulted parameters;
3. every implicit-member argument (`.someCase`) **names a real case** of the
   parameter's enum type;
4. every `switch` over a project enum is **exhaustive** or has a `default`.

It does **not** type-check, so a clean run does not prove the app builds —
it proves the syntax and the project's own API surface are self-consistent.
Exit code is non-zero when anything fails, so it drops straight into CI.
