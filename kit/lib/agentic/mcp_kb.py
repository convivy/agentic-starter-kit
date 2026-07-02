#!/usr/bin/env python3
"""mcp_kb — serve the knowledge index to Claude sessions over MCP (stdio).

The one kit component with a third-party dependency: the `mcp` package
(install.sh installs it). Registered with `claude mcp add kb`; the tools
surface in sessions as mcp__kb__kb_search, mcp__kb__kb_get,
mcp__kb__kb_list_topics.
"""
import os
import pathlib
import sqlite3

from mcp.server.fastmcp import FastMCP

ROOT = pathlib.Path(os.environ.get("AGENTIC_ROOT", pathlib.Path.home() / "agentic"))
DB = ROOT / ".index" / "index.db"

mcp = FastMCP("kb")


def _con():
    return sqlite3.connect(f"file:{DB}?mode=ro", uri=True)


@mcp.tool()
def kb_search(query: str, limit: int = 8) -> list[dict]:
    """Full-text search the knowledge base. Returns id, title, kind, and a snippet."""
    con = _con()
    try:
        rows = con.execute(
            "SELECT id, title, kind, snippet(docs, 6, '[', ']', ' … ', 12) "
            "FROM docs WHERE docs MATCH ? ORDER BY rank LIMIT ?",
            (query, limit),
        ).fetchall()
    except sqlite3.Error as e:
        # FTS5 MATCH has its own query syntax; a stray quote or operator is a
        # user error, not a crash.
        return [{"error": f"bad search query ({e}); try plain words"}]
    finally:
        con.close()
    return [{"id": r[0], "title": r[1], "kind": r[2], "snippet": r[3]} for r in rows]


@mcp.tool()
def kb_get(id: str) -> dict:
    """Fetch one doc's full body by its frontmatter id."""
    con = _con()
    r = con.execute(
        "SELECT id, title, kind, status, body FROM docs WHERE id = ?", (id,)
    ).fetchone()
    con.close()
    if not r:
        return {"error": f"no doc with id {id!r}"}
    return {"id": r[0], "title": r[1], "kind": r[2], "status": r[3], "body": r[4]}


@mcp.tool()
def kb_list_topics() -> list[dict]:
    """List every doc id + title + kind, for browsing."""
    con = _con()
    rows = con.execute("SELECT id, title, kind FROM docs ORDER BY id").fetchall()
    con.close()
    return [{"id": r[0], "title": r[1], "kind": r[2]} for r in rows]


if __name__ == "__main__":
    mcp.run()
