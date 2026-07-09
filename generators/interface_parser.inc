#!/usr/bin/env python3
"""Structural public-interface parser for simple_model.

Outputs TSV rows:
  line<TAB>kind<TAB>name<TAB>signature<TAB>parser
"""
from __future__ import annotations

import ast
import re
import sys
from pathlib import Path


IDENT = r"[A-Za-z_][A-Za-z0-9_]*"


def emit(line: int, kind: str, name: str, signature: str, parser: str) -> None:
    if re.fullmatch(IDENT, name):
        print(f"{line}\t{kind}\t{name}\t{signature.strip()}\t{parser}")


def parse_python(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
        tree = ast.parse(text, filename=str(path))
    except (SyntaxError, UnicodeDecodeError):
        return 1
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            emit(node.lineno, "class", node.name, f"class {node.name}", "python_ast")
        elif isinstance(node, ast.AsyncFunctionDef):
            emit(node.lineno, "async def", node.name, f"async def {node.name}", "python_ast")
        elif isinstance(node, ast.FunctionDef):
            emit(node.lineno, "def", node.name, f"def {node.name}", "python_ast")
    return 0


def strip_js_comments_and_strings(line: str, in_block: bool) -> tuple[str, bool]:
    out: list[str] = []
    i = 0
    quote = ""
    while i < len(line):
        c = line[i]
        nxt = line[i + 1] if i + 1 < len(line) else ""
        if in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 2
            else:
                i += 1
            out.append(" ")
            continue
        if quote:
            if c == "\\":
                out.extend("  ")
                i += 2
                continue
            if c == quote:
                quote = ""
            out.append(" ")
            i += 1
            continue
        if c == "/" and nxt == "*":
            in_block = True
            out.extend("  ")
            i += 2
            continue
        if c == "/" and nxt == "/":
            out.extend(" " * (len(line) - i))
            break
        if c in ("'", '"', "`"):
            quote = c
            out.append(" ")
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out), in_block


def brace_delta(line: str) -> int:
    return line.count("{") - line.count("}")


def parse_js_like(path: Path) -> int:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return 1
    depth = 0
    in_block = False
    exported: set[tuple[str, str]] = set()
    decl = re.compile(
        rf"^\s*export\s+(?:default\s+)?(?:(async)\s+)?"
        rf"(class|function|const|let|var|interface|type|enum)\s+({IDENT})\b"
    )
    named = re.compile(r"^\s*export\s*\{([^}]+)\}")
    for lineno, raw in enumerate(lines, 1):
        clean, in_block = strip_js_comments_and_strings(raw, in_block)
        if depth == 0:
            m = decl.match(clean)
            if m:
                async_kw, kind, name = m.groups()
                out_kind = f"async {kind}" if async_kw else kind
                if (out_kind, name) not in exported:
                    exported.add((out_kind, name))
                    emit(lineno, out_kind, name, raw.strip(), "js_structural")
            m = named.match(clean)
            if m:
                for part in m.group(1).split(","):
                    piece = part.strip()
                    if not piece:
                        continue
                    piece = re.sub(r"\s+as\s+" + IDENT + r"$", "", piece).strip()
                    name = piece.split()[0] if piece.split() else ""
                    if ("export", name) not in exported:
                        exported.add(("export", name))
                        emit(lineno, "export", name, f"export {{{name}}}", "js_structural")
        depth = max(0, depth + brace_delta(clean))
    return 0


def parse_go(path: Path) -> int:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return 1
    depth = 0
    in_block = False
    decl = re.compile(r"^\s*(func|type|const|var)\s+([A-Z][A-Za-z0-9_]*)\b")
    method = re.compile(r"^\s*func\s+\([^)]*\)\s+([A-Z][A-Za-z0-9_]*)\b")
    for lineno, raw in enumerate(lines, 1):
        clean, in_block = strip_js_comments_and_strings(raw, in_block)
        if depth == 0:
            m = decl.match(clean)
            if m:
                emit(lineno, m.group(1), m.group(2), raw.strip(), "go_structural")
            else:
                m = method.match(clean)
                if m:
                    emit(lineno, "method", m.group(1), raw.strip(), "go_structural")
        depth = max(0, depth + brace_delta(clean))
    return 0


def parse_rust(path: Path) -> int:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return 1
    depth = 0
    in_block = False
    decl = re.compile(rf"^\s*pub(?:\([^)]*\))?\s+(fn|struct|enum|trait|const|static|type)\s+({IDENT})\b")
    for lineno, raw in enumerate(lines, 1):
        clean, in_block = strip_js_comments_and_strings(raw, in_block)
        if depth == 0:
            m = decl.match(clean)
            if m:
                emit(lineno, m.group(1), m.group(2), raw.strip(), "rust_structural")
        depth = max(0, depth + brace_delta(clean))
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: interface_parser.inc <file>", file=sys.stderr)
        return 64
    path = Path(sys.argv[1])
    suffix = path.suffix.lower()
    if suffix == ".py":
        return parse_python(path)
    if suffix in {".ts", ".tsx", ".js", ".jsx"}:
        return parse_js_like(path)
    if suffix == ".go":
        return parse_go(path)
    if suffix == ".rs":
        return parse_rust(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
