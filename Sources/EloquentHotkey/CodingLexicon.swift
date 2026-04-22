import Foundation

enum CodingLexicon {
    static let contextualPhrases: [String] = [
        "Git",
        "GitHub",
        "repo",
        "repository",
        "README",
        "main",
        "main branch",
        "origin main",
        "origin/main",
        "pull request",
        "PR",
        "commit",
        "branch",
        "merge",
        "rebase",
        "cherry-pick",
        "Swift",
        "SwiftUI",
        "Xcode",
        "Codex",
        "Cursor",
        "Claude",
        "OpenAI",
        "ChatGPT",
        "API",
        "JSON",
        "MCP",
        "SDK",
        "LLM",
        "GraphQL",
        "TypeScript",
        "JavaScript",
        "PostgreSQL",
        "macOS",
        "iOS",
        "CLI",
        "Terminal",
    ]

    static let cleanupGuidance = """
    Preserve common coding and Git terms like Git, GitHub, repo, repository, README, main, main branch, origin/main, pull request, PR, commit, branch, merge, rebase, Swift, SwiftUI, Xcode, Codex, Cursor, Claude, OpenAI, ChatGPT, API, JSON, MCP, SDK, LLM, GraphQL, TypeScript, JavaScript, PostgreSQL, macOS, iOS, CLI, and Terminal.
    Prefer coding meanings when the transcript clearly sounds like software work, for example GitHub instead of get her, main instead of Maine, origin/main instead of origin Maine, repo instead of repro, README instead of read me, and pull request instead of pool request.
    Keep the exact casing for technical words unless the surrounding sentence makes a different spelling unambiguous.
    """
}
