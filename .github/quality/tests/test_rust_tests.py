"""Tests for rust_tests.py: which Rust lines belong to tests."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import rust_tests  # noqa: E402


def lines_of(src, needle):
    return [i + 1 for i, line in enumerate(src.split("\n")) if needle in line]


class TestRegions(unittest.TestCase):
    def test_cfg_test_module_with_nested_module(self):
        src = (
            "fn prod_a() {}\n#[cfg(test)]\nmod tests {\n    mod inner {\n"
            '        fn x() { let s = "}"; }\n    }\n    fn y() {}\n}\nfn prod_b() {}\n'
        )
        self.assertEqual(rust_tests.rust_test_lines(src), set(range(2, 9)))

    def test_cfg_test_function(self):
        src = "fn prod() -> u8 { 1 }\n#[cfg(test)]\nfn helper() -> u8 {\n    2\n}\nfn prod2() {}\n"
        self.assertEqual(rust_tests.rust_test_lines(src), {2, 3, 4, 5})

    def test_out_of_line_module_ends_at_semicolon(self):
        src = "pub mod a;\n#[cfg(test)]\nmod tests;\npub mod b;\n"
        self.assertEqual(rust_tests.rust_test_lines(src), {2, 3})

    def test_braces_inside_literals_and_comments_are_ignored(self):
        src = r'''fn prod() {
    let a = "{ not a brace";
    let b = r#"} " still raw { "#;
    let c = '{';
    let d = '}';
    let e = '\'';
    let f = b'{';
    /* } block comment { /* nested } */ */
    // } line comment {
}
#[cfg(test)]
mod tests {
    fn t<'a>(x: &'a str) -> &'a str { let s = "}}}"; let r = r"{"; x }
    // }
    /* { */
    const C: char = '}';
}
fn after() {}
'''
        got = rust_tests.rust_test_lines(src)
        want = set(range(lines_of(src, "#[cfg(test)]")[0], lines_of(src, "const C")[0] + 2))
        self.assertEqual(got, want)
        self.assertEqual(got & set(range(1, 11)), set())

    def test_cfg_predicates(self):
        src = (
            '#[cfg(all(test, feature = "x"))]\nmod t { fn a() {} }\n#[cfg(not(test))]\nfn real() {}\n'
            '#[cfg(any(test, feature = "y"))]\nfn shared() {}\n#[cfg(any(test, all(test, unix)))]\nfn only_test() {}\n'
        )
        self.assertEqual(rust_tests.rust_test_lines(src), {1, 2, 7, 8})

    def test_doc_comments_attributes_test_fns_and_fields(self):
        src = (
            "/// Helper for the tests.\n#[allow(dead_code)]\n#[cfg(test)]\npub(crate) fn helper() {}\n\n"
            "#[tokio::test]\nasync fn t() {\n    assert!(true);\n}\n#[test]\nfn t2() {}\n"
            "struct S {\n    a: u8,\n    #[cfg(test)]\n    b: u8,\n}\n"
        )
        self.assertEqual(rust_tests.rust_test_lines(src), {1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 14, 15})

    def test_use_const_and_macro_items(self):
        src = r'''impl<'a> Foo<'a> {
    fn s(&self) -> &'static str { r##"a "# } { b"## }
    fn q(&self) -> char { '"' }
    fn e(&self) -> &str { "a\"}" }
    fn bs(&self) -> &[u8] { b"}" }
}
#[cfg(test)]
use super::*;
#[cfg(test)]
const X: Foo = Foo { a: 1 };
#[cfg(test)]
mockall::mock! {
    pub Thing {}
}
fn last() {}
'''
        self.assertEqual(rust_tests.rust_test_lines(src), set(range(7, 15)))


class TestParseDiff(unittest.TestCase):
    def test_github_patch_with_context(self):
        patch = "@@ -1,4 +1,5 @@\n a\n--- old\n+@@ -9 +9 @@\n+new\n b\n c\n@@ -10,2 +11,1 @@\n k\n-z\n\\ No newline at end of file"
        self.assertEqual(rust_tests.parse_diff_lines(patch), ([2, 11], [2, 3]))

    def test_new_file(self):
        self.assertEqual(rust_tests.parse_diff_lines("@@ -0,0 +1,2 @@\n+a\n+b"), ([], [1, 2]))


if __name__ == "__main__":
    unittest.main()
