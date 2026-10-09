//! Source-level guards for wiring a runtime test cannot reach (#553).
//!
//! Some links run only against process-wide state — the identity deletion's
//! real store and effects, the in-memory stores it empties — so the parallel
//! suite cannot execute them. Their guards read the source instead, and a
//! `find` + `contains` over the raw file let them pass on their own test
//! text, on a commented-out call or on a call wrapped to do nothing (PR #565
//! review). These helpers close that:
//!
//! - only the production part of the file is read, never its test module;
//! - comments are dropped, so a call kept in a comment is not a call;
//! - the item must appear exactly once: a renamed or re-signed item fails
//!   instead of matching something else;
//! - a body is compared whole, not searched, so nothing can be added around
//!   the expected call.
//!
//! Whitespace is ignored throughout, so a reformat never trips a guard.

/// The production code of a source file, normalized for matching: its test
/// module cut off, comments dropped, every whitespace character removed.
pub(crate) fn production_code(source: &str) -> String {
    let source = source.replace("\r\n", "\n");
    let production = source
        .split("\n#[cfg(test)]\nmod tests")
        .next()
        .unwrap_or_default();
    production
        .lines()
        .map(strip_line_comment)
        .collect::<String>()
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect()
}

/// `line` without its `//` comment. A `//` inside a string literal (an odd
/// number of quotes before it) is code, not a comment.
fn strip_line_comment(line: &str) -> &str {
    let mut from = 0;
    while let Some(at) = line[from..].find("//") {
        let at = from + at;
        if line[..at].matches('"').count().is_multiple_of(2) {
            return &line[..at];
        }
        from = at + 2;
    }
    line
}

/// The body, between its outer braces, of the one item in `code` (from
/// [`production_code`]) whose header is exactly `signature`.
pub(crate) fn item_body(code: &str, signature: &str) -> Result<String, String> {
    let header: String = signature.chars().filter(|c| !c.is_whitespace()).collect();
    let mut found = code.match_indices(&header).map(|(at, _)| at);
    let (Some(at), None) = (found.next(), found.next()) else {
        return Err(format!("`{signature}` must appear exactly once"));
    };
    let open = at + header.len();
    if !code[open..].starts_with('{') {
        return Err(format!("`{signature}` is not followed by its body"));
    }
    let mut depth = 0usize;
    for (offset, c) in code[open..].char_indices() {
        match c {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    return Ok(code[open + 1..open + offset].to_string());
                }
            }
            _ => {}
        }
    }
    Err(format!("`{signature}` has no closing brace"))
}

/// The item whose header is `signature` has exactly the body `expected`.
pub(crate) fn expect_body(code: &str, signature: &str, expected: &str) -> Result<(), String> {
    let body = item_body(code, signature)?;
    let expected: String = expected.chars().filter(|c| !c.is_whitespace()).collect();
    if body == expected {
        Ok(())
    } else {
        Err(format!(
            "`{signature}` changed. If that is intended, update its guard.\n  expected: {expected}\n  found:    {body}"
        ))
    }
}

/// `source` with `from` replaced by `to` in its production part — a mutant
/// for a guard's negative control. Panics when the production code does not
/// change, so a control can never test an unmutated file by accident.
pub(crate) fn mutant(source: &str, from: &str, to: &str) -> String {
    let source = source.replace("\r\n", "\n");
    let (production, tests) = match source.split_once("\n#[cfg(test)]\nmod tests") {
        Some((production, tests)) => (production, format!("\n#[cfg(test)]\nmod tests{tests}")),
        None => (source.as_str(), String::new()),
    };
    assert!(
        production.contains(from),
        "the mutation `{from}` does not apply"
    );
    let mutated = format!("{}{tests}", production.replacen(from, to, 1));
    assert_ne!(
        production_code(&mutated),
        production_code(&source),
        "the mutation `{from}` → `{to}` changes no code",
    );
    mutated
}

#[cfg(test)]
mod tests {
    use super::*;

    const SOURCE: &str = "\
/// Calls `run()` in its docs.
pub fn run() -> u8 {
    // a comment with a { brace
    let url = \"https://x\";
    helper(url, { 1 })
}

fn helper(_: &str, n: u8) -> u8 { n }

#[cfg(test)]
mod tests {
    fn guard() { let _ = \"pub fn run() -> u8 { other() }\"; }
}
";

    #[test]
    fn a_body_is_read_from_production_without_comments() {
        let code = production_code(SOURCE);
        assert_eq!(
            item_body(&code, "pub fn run() -> u8").unwrap(),
            "leturl=\"https://x\";helper(url,{1})",
        );
        assert!(expect_body(
            &code,
            "pub fn run() -> u8",
            "let url = \"https://x\"; helper(url, { 1 })",
        )
        .is_ok());
    }

    #[test]
    fn a_missing_or_repeated_item_fails_closed() {
        let code = production_code(SOURCE);
        assert!(item_body(&code, "pub fn run(flag: bool) -> u8").is_err());
        let twice = production_code(&format!("{SOURCE}\npub fn run() -> u8 {{ 2 }}\n"));
        // Appended after the test module, so it is not production code…
        assert!(item_body(&twice, "pub fn run() -> u8").is_ok());
        // …but a second copy in production is ambiguous.
        let twice =
            production_code(&SOURCE.replace("fn helper", "pub fn run() -> u8 { 2 }\nfn helper"));
        assert!(item_body(&twice, "pub fn run() -> u8").is_err());
    }

    #[test]
    fn a_changed_body_fails_the_comparison() {
        let wrapped = mutant(SOURCE, "helper(url, { 1 })", "helper(url, { 1 }).min(0)");
        assert!(expect_body(
            &production_code(&wrapped),
            "pub fn run() -> u8",
            "let url = \"https://x\"; helper(url, { 1 })",
        )
        .is_err());
    }

    #[test]
    #[should_panic(expected = "changes no code")]
    fn a_mutant_that_only_touches_a_comment_is_refused() {
        mutant(SOURCE, "a comment", "another comment");
    }
}
