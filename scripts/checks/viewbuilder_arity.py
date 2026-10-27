#!/usr/bin/env python3
"""Finds SwiftUI ViewBuilder blocks with more than 10 children, which the compiler refuses.

Nobody here has a Mac, so the compiler is a CI run away and costs ten billed minutes per macOS minute;
this finds the commonest way a screen stops compiling in a few seconds on Linux.

usage: viewbuilder_arity.py [--max 10] [files...]    (default: every tracked .swift file)

It is a heuristic over the syntax tree (tree-sitter), not the type checker: it looks at the calls to
the usual containers with a trailing closure, at `body`, and at members marked @ViewBuilder. A `#if`
counts as its biggest branch and local declarations count for nothing. Exit status 1 when a block is
over the limit; the output is GitHub annotations.
"""
import subprocess
import sys
from pathlib import Path

import tree_sitter
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[2]

CONTAINERS = {
    "VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack", "List", "Group", "Section", "ScrollView", "Form",
    "NavigationStack", "NavigationView", "TabView", "Menu", "Grid", "GridRow", "LabeledContent", "ControlGroup",
    "DisclosureGroup", "ToolbarItemGroup", "GroupBox", "HSplitView", "VSplitView", "ViewThatFits", "ContextMenu",
    "SwiftUI.VStack", "Canvas", "Chart", "TimelineView",
}
NOT_VIEWS = {"property_declaration", "typealias_declaration", "function_declaration", "comment", "multiline_comment"}

parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))


def count(statements: tree_sitter.Node) -> int:
    """The children a `statements` node produces, with `#if` / `#else` taken as the biggest branch."""
    current = 0
    frames: list[tuple[int, list[int]]] = []  # (children before the #if, the branches closed so far)
    for child in statements.children:
        if child.type == "directive":
            word = child.children[0].type if child.children else ""
            if word == "#if":
                frames.append((current, []))
                current = 0
            elif word in ("#else", "#elseif") and frames:
                base, branches = frames.pop()
                frames.append((base, branches + [current]))
                current = 0
            elif word == "#endif" and frames:
                base, branches = frames.pop()
                current = base + max(branches + [current])
            continue
        if child.type in NOT_VIEWS or child.type == ";":
            continue
        current += 1
    return current


def statements_of(node: tree_sitter.Node) -> tree_sitter.Node | None:
    return next((child for child in node.children if child.type == "statements"), None)


def walk(node: tree_sitter.Node, path: str, limit: int, found: list[tuple[str, int, str]]) -> None:
    if node.type == "call_expression":
        name = node.children[0].text.decode().split("<")[0]
        if name in CONTAINERS:
            for suffix in (c for c in node.children if c.type == "call_suffix"):
                for closure in (c for c in suffix.children if c.type == "lambda_literal"):
                    statements = statements_of(closure)
                    if statements is not None and (n := count(statements)) > limit:
                        found.append((path, closure.start_point[0] + 1, f"{name} {{ }} has {n} children"))
    elif node.type in ("property_declaration", "function_declaration"):
        modifiers = next((c for c in node.children if c.type == "modifiers"), None)
        is_builder = modifiers is not None and b"ViewBuilder" in modifiers.text
        is_body = node.type == "property_declaration" and b"var body" in node.text[:60]
        if is_builder or is_body:
            body = next((c for c in node.children if c.type in ("computed_property", "function_body")), None)
            statements = statements_of(body) if body is not None else None
            if statements is not None and (n := count(statements)) > limit:
                found.append((path, node.start_point[0] + 1, f"@ViewBuilder/body has {n} children"))
    for child in node.children:
        walk(child, path, limit, found)


def main() -> int:
    args = sys.argv[1:]
    limit = 10
    if args[:1] == ["--max"]:
        limit = int(args[1])
        args = args[2:]
    if not args:
        args = subprocess.run(
            ["git", "ls-files", "*.swift"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.split()
    found: list[tuple[str, int, str]] = []
    for name in args:
        path = Path(name) if Path(name).is_absolute() else ROOT / name
        walk(parser.parse(path.read_bytes()).root_node, name, limit, found)
    for name, line, message in found:
        print(f"::error file={name},line={line}::{message}; SwiftUI builds at most {limit} views per block")
    print(f"{len(found)} block(s) over {limit}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
