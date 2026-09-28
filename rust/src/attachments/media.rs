//! What may be attached, decided by the bytes — never by the file name or a
//! MIME type the platform or the peer claims.
//!
//! Sent: JPEG, PNG and PDF. Images are decoded and re-encoded before they
//! leave the device, which drops EXIF (GPS position, device, time) and any
//! other metadata; the orientation is applied to the pixels first so a phone
//! photo does not arrive sideways. v1 re-encodes too
//! (`MediaValidationService.validateAndSanitizeImageLight`).
use std::io::Cursor;

use anyhow::{anyhow, bail, Result};
use image::{DynamicImage, ImageDecoder, ImageFormat, ImageReader, Limits};

use crate::api::types::FileType;
use crate::attachments::MAX_ATTACHMENT_BYTES;

/// Largest image side accepted, in pixels.
const MAX_IMAGE_SIDE: u32 = 10_000;
/// Memory the decoder may allocate: bounds a decompression bomb.
const MAX_DECODE_ALLOC: u64 = 256 * 1024 * 1024;
/// JPEG quality of the re-encoded image. v1 uses 95; 90 keeps a receipt
/// perfectly legible at a noticeably smaller upload.
const JPEG_QUALITY: u8 = 90;
/// Longest file name kept, in characters.
const MAX_NAME_CHARS: usize = 120;

/// A file type recognised by its signature.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Jpeg,
    Png,
    Pdf,
}

impl Kind {
    pub fn mime(self) -> &'static str {
        match self {
            Kind::Jpeg => "image/jpeg",
            Kind::Png => "image/png",
            Kind::Pdf => "application/pdf",
        }
    }

    pub fn file_type(self) -> FileType {
        match self {
            Kind::Jpeg | Kind::Png => FileType::Image,
            Kind::Pdf => FileType::Document,
        }
    }
}

/// Recognise JPEG, PNG and PDF by their leading bytes.
pub fn sniff(bytes: &[u8]) -> Option<Kind> {
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some(Kind::Jpeg)
    } else if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        Some(Kind::Png)
    } else if bytes.starts_with(b"%PDF-") {
        Some(Kind::Pdf)
    } else {
        None
    }
}

/// Marks bytes that are not what their sender said they are.
pub const UNKNOWN_MIME: &str = "application/octet-stream";

/// The type to report for a received file: what its bytes are when they are
/// JPEG, PNG or PDF, otherwise what the sender declared — unless the sender
/// declared one of those three, in which case the bytes have just proved it
/// false and the file is [`UNKNOWN_MIME`]. Dart decides from this what it may
/// hand to another app, so a claimed PDF that is not one must not keep the
/// claim (#595 review).
pub fn reported_mime(bytes: &[u8], declared: &str) -> String {
    if let Some(kind) = sniff(bytes) {
        return kind.mime().to_string();
    }
    let claims_sniffable = [Kind::Jpeg, Kind::Png, Kind::Pdf]
        .iter()
        .any(|k| k.mime().eq_ignore_ascii_case(declared.trim()));
    if claims_sniffable {
        UNKNOWN_MIME.to_string()
    } else {
        declared.to_string()
    }
}

/// A file ready to be encrypted and uploaded.
#[derive(Debug)]
pub struct Prepared {
    pub kind: Kind,
    /// The bytes to encrypt: re-encoded for images, untouched for PDFs.
    pub bytes: Vec<u8>,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

/// Check and clean a file the user picked, before it is encrypted.
///
/// Errors are markers Dart maps to messages: `FileTooLarge`,
/// `UnsupportedFileType`, `InvalidImage`.
pub fn prepare_for_send(bytes: Vec<u8>) -> Result<Prepared> {
    if bytes.len() > MAX_ATTACHMENT_BYTES {
        bail!("FileTooLarge: {} bytes exceeds the 25 MB limit", bytes.len());
    }
    let kind = sniff(&bytes).ok_or_else(|| anyhow!("UnsupportedFileType: not a JPEG, PNG or PDF"))?;
    match kind {
        Kind::Pdf => Ok(Prepared { kind, bytes, width: None, height: None }),
        Kind::Jpeg | Kind::Png => {
            let image = decode(&bytes, kind)?;
            let (width, height) = (image.width(), image.height());
            let bytes = encode(&image, kind)?;
            if bytes.len() > MAX_ATTACHMENT_BYTES {
                bail!("FileTooLarge: {} bytes after re-encoding exceeds the 25 MB limit", bytes.len());
            }
            Ok(Prepared { kind, bytes, width: Some(width), height: Some(height) })
        }
    }
}

fn decode(bytes: &[u8], kind: Kind) -> Result<DynamicImage> {
    let format = match kind {
        Kind::Jpeg => ImageFormat::Jpeg,
        Kind::Png => ImageFormat::Png,
        Kind::Pdf => unreachable!("PDFs are not decoded"),
    };
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_IMAGE_SIDE);
    limits.max_image_height = Some(MAX_IMAGE_SIDE);
    limits.max_alloc = Some(MAX_DECODE_ALLOC);
    let mut reader = ImageReader::with_format(Cursor::new(bytes), format);
    reader.limits(limits);
    let mut decoder = reader
        .into_decoder()
        .map_err(|e| anyhow!("InvalidImage: {e}"))?;
    let orientation = decoder.orientation().map_err(|e| anyhow!("InvalidImage: {e}"))?;
    let mut image = DynamicImage::from_decoder(decoder).map_err(|e| anyhow!("InvalidImage: {e}"))?;
    image.apply_orientation(orientation);
    Ok(image)
}

fn encode(image: &DynamicImage, kind: Kind) -> Result<Vec<u8>> {
    let mut out = Cursor::new(Vec::new());
    match kind {
        Kind::Jpeg => {
            // JPEG has no alpha: flatten so an RGBA source still encodes.
            let rgb = DynamicImage::ImageRgb8(image.to_rgb8());
            let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, JPEG_QUALITY);
            rgb.write_with_encoder(encoder)
        }
        Kind::Png => image.write_to(&mut out, ImageFormat::Png),
        Kind::Pdf => unreachable!("PDFs are not re-encoded"),
    }
    .map_err(|e| anyhow!("InvalidImage: re-encoding failed: {e}"))?;
    Ok(out.into_inner())
}

/// A file name safe to show and to save under: the last path component only,
/// no control characters, bounded length. The peer chooses it, so it is
/// untrusted — `../../x` must not escape a directory.
pub fn sanitize_filename(name: &str) -> String {
    let last = name.rsplit(['/', '\\']).next().unwrap_or("");
    // `: * ? " < > |` too: legal on the peer's side, but creating the file
    // fails on Windows and FAT/exFAT storage.
    let clean: String = last
        .chars()
        .filter(|c| {
            !c.is_control()
                && !is_invisible_format(*c)
                && !matches!(c, ':' | '*' | '?' | '"' | '<' | '>' | '|')
        })
        .collect();
    let clean = clean.trim().trim_start_matches('.').trim();
    if clean.is_empty() {
        return "attachment".to_string();
    }
    if clean.chars().count() <= MAX_NAME_CHARS {
        return clean.to_string();
    }
    // Keep the extension when shortening.
    match clean.rsplit_once('.') {
        Some((stem, ext)) if ext.chars().count() <= 10 => {
            let keep = MAX_NAME_CHARS - ext.chars().count() - 1;
            format!("{}.{ext}", stem.chars().take(keep).collect::<String>())
        }
        _ => clean.chars().take(MAX_NAME_CHARS).collect(),
    }
}

/// Bidirectional overrides and zero-width characters: not controls, but they
/// let a name lie about itself — `recibo\u{202E}fdp.exe` shows as
/// `reciboexe.pdf`.
fn is_invisible_format(c: char) -> bool {
    matches!(
        c,
        '\u{200B}'..='\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2060}'..='\u{2069}' | '\u{FEFF}'
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgb, RgbImage};

    #[test]
    fn reported_mime_trusts_the_bytes_over_the_claim() {
        assert_eq!(reported_mime(b"%PDF-1.7 ...", "image/png"), "application/pdf");
        assert_eq!(
            reported_mime(&[0xFF, 0xD8, 0xFF, 0xE0], "application/pdf"),
            "image/jpeg"
        );
    }

    #[test]
    fn reported_mime_drops_a_sniffable_claim_the_bytes_disprove() {
        for claim in ["application/pdf", "image/jpeg", "IMAGE/PNG ", "image/png"] {
            assert_eq!(
                reported_mime(b"MZ\x90\x00 not a pdf", claim),
                UNKNOWN_MIME,
                "{claim}"
            );
        }
    }

    #[test]
    fn reported_mime_keeps_a_claim_it_cannot_check() {
        let docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
        assert_eq!(reported_mime(b"PK\x03\x04", docx), docx);
        assert_eq!(
            reported_mime(b"\x00\x00\x00\x18ftypmp42", "video/mp4"),
            "video/mp4"
        );
    }

    fn jpeg(width: u32, height: u32) -> Vec<u8> {
        let img = DynamicImage::ImageRgb8(RgbImage::from_pixel(width, height, Rgb([200, 30, 30])));
        let mut out = Cursor::new(Vec::new());
        img.write_to(&mut out, ImageFormat::Jpeg).unwrap();
        out.into_inner()
    }

    /// Splice an APP1/Exif segment right after SOI, carrying an orientation
    /// tag and a fake GPS marker string.
    fn with_exif(jpeg: &[u8], orientation: u16) -> Vec<u8> {
        let mut tiff = Vec::new();
        tiff.extend_from_slice(b"MM\x00\x2A\x00\x00\x00\x08"); // big-endian TIFF, IFD at 8
        tiff.extend_from_slice(&1u16.to_be_bytes()); // one entry
        tiff.extend_from_slice(&0x0112u16.to_be_bytes()); // Orientation
        tiff.extend_from_slice(&3u16.to_be_bytes()); // SHORT
        tiff.extend_from_slice(&1u32.to_be_bytes()); // count
        tiff.extend_from_slice(&orientation.to_be_bytes());
        tiff.extend_from_slice(&[0, 0]);
        tiff.extend_from_slice(&0u32.to_be_bytes()); // no next IFD
        tiff.extend_from_slice(b"GPS-SECRET-LOCATION");
        let mut app1 = b"Exif\x00\x00".to_vec();
        app1.extend_from_slice(&tiff);
        let len = (app1.len() + 2) as u16;
        let mut out = jpeg[..2].to_vec(); // SOI
        out.extend_from_slice(&[0xFF, 0xE1]);
        out.extend_from_slice(&len.to_be_bytes());
        out.extend_from_slice(&app1);
        out.extend_from_slice(&jpeg[2..]);
        out
    }

    fn contains(haystack: &[u8], needle: &[u8]) -> bool {
        haystack.windows(needle.len()).any(|w| w == needle)
    }

    #[test]
    fn sniffs_by_content_not_by_name() {
        assert_eq!(sniff(&jpeg(2, 2)), Some(Kind::Jpeg));
        assert_eq!(sniff(b"%PDF-1.7\n..."), Some(Kind::Pdf));
        assert_eq!(sniff(b"\x89PNG\r\n\x1a\n...."), Some(Kind::Png));
        assert_eq!(sniff(b"GIF89a"), None);
        assert_eq!(sniff(b"PK\x03\x04 docx"), None);
    }

    #[test]
    fn an_image_loses_its_metadata_and_keeps_its_orientation() {
        let original = with_exif(&jpeg(40, 20), 6); // 6 = rotate 90° clockwise
        assert!(contains(&original, b"GPS-SECRET-LOCATION"));
        let p = prepare_for_send(original).unwrap();
        assert_eq!(p.kind, Kind::Jpeg);
        assert!(!contains(&p.bytes, b"Exif"), "EXIF must not leave the device");
        assert!(!contains(&p.bytes, b"GPS-SECRET-LOCATION"));
        // The rotation is now in the pixels: 40×20 turned becomes 20×40.
        assert_eq!((p.width, p.height), (Some(20), Some(40)));
        assert_eq!(sniff(&p.bytes), Some(Kind::Jpeg));
    }

    #[test]
    fn a_png_stays_a_png() {
        let img = DynamicImage::ImageRgba8(image::RgbaImage::from_pixel(3, 5, image::Rgba([1, 2, 3, 128])));
        let mut out = Cursor::new(Vec::new());
        img.write_to(&mut out, ImageFormat::Png).unwrap();
        let p = prepare_for_send(out.into_inner()).unwrap();
        assert_eq!((p.kind, p.width, p.height), (Kind::Png, Some(3), Some(5)));
    }

    #[test]
    fn a_pdf_passes_through_untouched() {
        let pdf = b"%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF".to_vec();
        let p = prepare_for_send(pdf.clone()).unwrap();
        assert_eq!((p.kind, p.bytes), (Kind::Pdf, pdf));
    }

    #[test]
    fn refuses_what_it_cannot_vouch_for() {
        let err = |b: Vec<u8>| prepare_for_send(b).unwrap_err().to_string();
        assert!(err(b"hello".to_vec()).starts_with("UnsupportedFileType"));
        assert!(err(vec![0xFF, 0xD8, 0xFF, 0x00, 0x01]).starts_with("InvalidImage"));
        let mut huge = b"%PDF-".to_vec();
        huge.resize(MAX_ATTACHMENT_BYTES + 1, 0);
        assert!(err(huge).starts_with("FileTooLarge"));
    }

    #[test]
    fn file_names_cannot_escape_or_mislead() {
        assert_eq!(sanitize_filename("../../etc/passwd"), "passwd");
        assert_eq!(sanitize_filename("C:\\Users\\a\\recibo.pdf"), "recibo.pdf");
        assert_eq!(sanitize_filename("foto\u{202e}gpj.exe"), "fotogpj.exe");
        assert_eq!(sanitize_filename("a:b*c?\"d<e>f|.pdf"), "abcdef.pdf");
        assert_eq!(sanitize_filename("  "), "attachment");
        assert_eq!(sanitize_filename(".."), "attachment");
        let long = format!("{}.pdf", "a".repeat(300));
        let short = sanitize_filename(&long);
        assert!(short.ends_with(".pdf") && short.chars().count() == MAX_NAME_CHARS);
    }
}
