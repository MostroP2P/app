//! The chat message that carries an attachment.
//!
//! A JSON object sent as the text of an ordinary chat message (the inner
//! kind 1 of the chat envelope). v1 defines two shapes and parses every field
//! strictly (`as int`, `as String`), so both are reproduced field for field:
//!
//! ```json
//! {"type":"image_encrypted","blossom_url":"https://…/<sha256>","nonce":"<hex>",
//!  "mime_type":"image/jpeg","original_size":1,"width":1,"height":1,
//!  "filename":"…","encrypted_size":29}
//! {"type":"file_encrypted","file_type":"document","blossom_url":"…","nonce":"<hex>",
//!  "mime_type":"application/pdf","original_size":1,"filename":"…","encrypted_size":29}
//! ```
//!
//! `nonce` repeats the one at the head of the blob; readers ignore it and
//! decrypt with the blob's own. It is sent because v1 requires the field.
use serde::{Deserialize, Serialize};

use crate::api::types::FileType;
use crate::attachments::media::sanitize_filename;
use crate::attachments::MAX_BLOB_BYTES;
use crate::nostr::blossom;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AttachmentPayload {
    /// A JPEG or PNG, which v1 previews inline.
    #[serde(rename = "image_encrypted")]
    Image(ImagePayload),
    /// Anything else (`file_type`: `image` | `video` | `document`).
    #[serde(rename = "file_encrypted")]
    File(FilePayload),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ImagePayload {
    pub blossom_url: String,
    pub nonce: String,
    pub mime_type: String,
    pub original_size: u64,
    pub width: u32,
    pub height: u32,
    pub filename: String,
    pub encrypted_size: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FilePayload {
    pub file_type: String,
    pub blossom_url: String,
    pub nonce: String,
    pub mime_type: String,
    pub original_size: u64,
    pub filename: String,
    pub encrypted_size: u64,
}

/// A received attachment, validated: what the chat stores and shows.
#[derive(Debug, Clone, PartialEq)]
pub struct IncomingAttachment {
    pub file_type: FileType,
    pub blossom_url: String,
    /// Hex SHA-256 of the encrypted blob, taken from the URL. The download is
    /// checked against it before decrypting.
    pub sha256: String,
    /// As declared by the sender. Only a label: what the bytes are is sniffed
    /// after decrypting.
    pub mime_type: String,
    pub file_name: String,
    pub original_size: u64,
    pub encrypted_size: u64,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

impl AttachmentPayload {
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).expect("attachment payload serializes")
    }
}

/// Read a chat message's text as an attachment, if it is one.
///
/// Anything that is not a well-formed, safe attachment — plain text, JSON of
/// another shape, a non-HTTPS URL, a URL without the blob hash, a size over
/// the limit — is `None`, and the message stays text.
pub fn parse(text: &str) -> Option<IncomingAttachment> {
    // v1 only considers text that starts with `{`.
    if !text.trim_start().starts_with('{') {
        return None;
    }
    let payload: AttachmentPayload = serde_json::from_str(text).ok()?;
    let (url, mime, name, original, encrypted, file_type, dims) = match payload {
        AttachmentPayload::Image(p) => (
            p.blossom_url,
            p.mime_type,
            p.filename,
            p.original_size,
            p.encrypted_size,
            FileType::Image,
            Some((p.width, p.height)),
        ),
        AttachmentPayload::File(p) => {
            let kind = match p.file_type.as_str() {
                "image" => FileType::Image,
                "video" => FileType::Video,
                _ => FileType::Document,
            };
            (p.blossom_url, p.mime_type, p.filename, p.original_size, p.encrypted_size, kind, None)
        }
    };
    let sha256 = blossom::sha256_from_url(&url)?;
    if !url.starts_with("https://") || encrypted > MAX_BLOB_BYTES as u64 {
        return None;
    }
    Some(IncomingAttachment {
        file_type,
        blossom_url: url,
        sha256,
        mime_type: mime,
        file_name: sanitize_filename(&name),
        original_size: original,
        encrypted_size: encrypted,
        width: dims.map(|d| d.0),
        height: dims.map(|d| d.1),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const HASH: &str = "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553";

    // Exactly what v1's `EncryptedImageUploadResult.toJson()` produces.
    fn v1_image() -> String {
        format!(
            r#"{{"type":"image_encrypted","blossom_url":"https://cdn.hzrd149.com/{HASH}","nonce":"0102030405060708090a0b0c","mime_type":"image/jpeg","original_size":524288,"width":1920,"height":1080,"filename":"receipt.jpg","encrypted_size":524316}}"#
        )
    }

    fn v1_pdf() -> String {
        format!(
            r#"{{"type":"file_encrypted","file_type":"document","blossom_url":"https://nostr.download/{HASH}","nonce":"0102030405060708090a0b0c","mime_type":"application/pdf","original_size":1048576,"filename":"bank.pdf","encrypted_size":1048604}}"#
        )
    }

    #[test]
    fn reads_a_v1_image() {
        let a = parse(&v1_image()).unwrap();
        assert_eq!(a.file_type, FileType::Image);
        assert_eq!(a.sha256, HASH);
        assert_eq!((a.width, a.height), (Some(1920), Some(1080)));
        assert_eq!(a.file_name, "receipt.jpg");
        assert_eq!(a.original_size, 524288);
    }

    #[test]
    fn reads_a_v1_pdf() {
        let a = parse(&v1_pdf()).unwrap();
        assert_eq!(a.file_type, FileType::Document);
        assert_eq!(a.mime_type, "application/pdf");
        assert_eq!(a.width, None);
    }

    #[test]
    fn what_it_writes_v1_reads_back_field_for_field() {
        // Round-trip through the typed payload: every field v1's fromJson
        // requires is present and of the JSON type it casts to.
        let v: serde_json::Value = serde_json::from_str(&v1_image()).unwrap();
        let ours: serde_json::Value =
            serde_json::from_str(&serde_json::from_str::<AttachmentPayload>(&v1_image()).unwrap().to_json())
                .unwrap();
        assert_eq!(ours, v);
        let v: serde_json::Value = serde_json::from_str(&v1_pdf()).unwrap();
        let ours: serde_json::Value =
            serde_json::from_str(&serde_json::from_str::<AttachmentPayload>(&v1_pdf()).unwrap().to_json())
                .unwrap();
        assert_eq!(ours, v);
    }

    #[test]
    fn plain_text_and_other_json_stay_text() {
        assert!(parse("hola, ya te transferí").is_none());
        assert!(parse(r#"{"type":"file","url":"https://x/y","name":"a","mime_type":"a/b"}"#).is_none());
        // A v1 image missing width/height is malformed for v1 too.
        assert!(parse(&v1_image().replace(r#""width":1920,"height":1080,"#, "")).is_none());
    }

    #[test]
    fn refuses_unsafe_urls_and_oversized_blobs() {
        assert!(parse(&v1_image().replace("https://", "http://")).is_none());
        assert!(parse(&v1_image().replace(HASH, "not-a-hash")).is_none());
        assert!(parse(&v1_image().replace("524316", &(MAX_BLOB_BYTES + 1).to_string())).is_none());
        // Compared as u64: 2^32 + 1 must not wrap to 1 on a 32-bit target.
        assert!(parse(&v1_image().replace("524316", "4294967297")).is_none());
    }

    #[test]
    fn a_hostile_file_name_is_defused() {
        let a = parse(&v1_pdf().replace("bank.pdf", "../../etc/passwd")).unwrap();
        assert_eq!(a.file_name, "passwd");
    }
}
