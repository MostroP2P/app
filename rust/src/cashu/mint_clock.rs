//! The mint's clock, for the verdicts on a mint quote that must not hang on
//! the device's (phase C3b-2).
//!
//! A quote's `expiry` is the mint's time; "now" read on the device is not. A
//! phone set a day ahead would call a fresh, still payable invoice expired —
//! and the collector would forget it, so a payment made afterwards would have
//! no quote left to mint with: sats at the mint the wallet cannot claim.
//!
//! The mint's own sense of time is not on offer where cdk looks for it:
//! NUT-06's `time` is optional, cdk-mintd leaves it out, and cdk refuses a
//! mint whose `time` is more than 30 s from the device's (`fetch_mint_info`,
//! cdk 0.18.1) — so a skewed device never sees one. Every HTTP server dates
//! its answers, though (`Date`, RFC 9110 §6.6.1), so that header of a
//! `GET /v1/info` is read instead. To the second, which is all a margin of
//! minutes needs.
//!
//! The offset to the device's clock is kept for [`OFFSET_LIFETIME`] per mint,
//! so an invoice screen asking every few seconds does not ask the mint the
//! time each round.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use cdk::mint_url::MintUrl;

/// How long a mint's clock offset is trusted before it is read again.
const OFFSET_LIFETIME: Duration = Duration::from_secs(5 * 60);

/// How long to wait for the mint to say what time it is.
const ASK_TIMEOUT: Duration = Duration::from_secs(10);

/// Each mint's clock minus the device's, in seconds, with when it was read.
fn offsets() -> std::sync::MutexGuard<'static, HashMap<String, (Instant, i64)>> {
    static OFFSETS: OnceLock<Mutex<HashMap<String, (Instant, i64)>>> = OnceLock::new();
    OFFSETS
        .get_or_init(Default::default)
        .lock()
        // A map of numbers: no invariant a panic could break halfway.
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn device_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// Unix time at `mint`, by its clock, or `None` when it cannot be told: the
/// mint did not answer, or its answer carried no date this can read. Whoever
/// asks then decides nothing that only the mint's time may decide.
pub(crate) async fn mint_now(mint: &MintUrl) -> Option<u64> {
    let key = mint.to_string();
    let cached = offsets()
        .get(&key)
        .filter(|(read_at, _)| read_at.elapsed() < OFFSET_LIFETIME)
        .map(|(_, offset)| *offset);
    let offset = match cached {
        Some(offset) => offset,
        None => {
            let offset = ask_offset(mint).await?;
            offsets().insert(key, (Instant::now(), offset));
            offset
        }
    };
    device_now().checked_add_signed(offset)
}

/// The mint's clock minus the device's, from the `Date` of its `/v1/info`.
async fn ask_offset(mint: &MintUrl) -> Option<i64> {
    let url = match mint.join_paths(&["v1", "info"]) {
        Ok(url) => url,
        Err(e) => {
            log::warn!("[cashu] no info URL to read {mint}'s clock: {e}");
            return None;
        }
    };
    let client = reqwest::Client::builder()
        .timeout(ASK_TIMEOUT)
        .build()
        .ok()?;
    let answer = match client.get(url).send().await {
        Ok(answer) => answer,
        Err(e) => {
            log::info!("[cashu] {mint}'s clock not read: {e}");
            return None;
        }
    };
    let asked_at = device_now();
    let Some(date) = answer
        .headers()
        .get(reqwest::header::DATE)
        .and_then(|value| value.to_str().ok())
        .and_then(parse_http_date)
    else {
        log::info!("[cashu] {mint} dates no answer: its clock is unknown");
        return None;
    };
    Some(date as i64 - asked_at as i64)
}

/// Unix time of an IMF-fixdate, `Sun, 06 Nov 1994 08:49:37 GMT` — the one
/// form RFC 9110 lets a server send. `None` for anything else.
fn parse_http_date(value: &str) -> Option<u64> {
    let parts: Vec<&str> = value.split_ascii_whitespace().collect();
    let [_weekday, day, month, year, time, "GMT"] = parts.as_slice() else {
        return None;
    };
    let day: u32 = day.parse().ok()?;
    let month = 1 + [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    .iter()
    .position(|name| name == month)? as u32;
    let year: i64 = year.parse().ok()?;
    let mut hms = time.split(':').map(str::parse::<u64>);
    let (Some(Ok(h)), Some(Ok(m)), Some(Ok(s)), None) =
        (hms.next(), hms.next(), hms.next(), hms.next())
    else {
        return None;
    };
    if !(1..=31).contains(&day) || h > 23 || m > 59 || s > 60 {
        return None;
    }
    let days = days_from_civil(year, month, day);
    u64::try_from(days * 86_400)
        .ok()?
        .checked_add(h * 3_600 + m * 60 + s)
}

/// Days from 1970-01-01 to the given date (proleptic Gregorian), after
/// Howard Hinnant's `days_from_civil`.
fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let month = i64::from(month);
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + i64::from(day) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

/// Drop what is known of `mint`'s clock, for a test mint on a port an
/// earlier one had.
#[cfg(test)]
pub(crate) fn forget_offset(mint: &MintUrl) {
    offsets().remove(&mint.to_string());
}

/// The `Date` a server would send at unix time `secs`, for test mints.
#[cfg(test)]
pub(crate) fn http_date(secs: u64) -> String {
    const WEEKDAYS: [&str; 7] = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"];
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let days = (secs / 86_400) as i64;
    // civil_from_days, the inverse of the above.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    let rest = secs % 86_400;
    format!(
        "{}, {day:02} {} {year} {:02}:{:02}:{:02} GMT",
        WEEKDAYS[(days % 7) as usize],
        MONTHS[(month - 1) as usize],
        rest / 3_600,
        rest % 3_600 / 60,
        rest % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_imf_fixdate_reads_as_unix_time() {
        // RFC 9110's own example.
        assert_eq!(
            parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT"),
            Some(784_111_777)
        );
        assert_eq!(parse_http_date("Thu, 01 Jan 1970 00:00:00 GMT"), Some(0));
        assert_eq!(
            parse_http_date("Tue, 29 Feb 2028 23:59:59 GMT"),
            Some(1_835_481_599)
        );
    }

    #[test]
    fn anything_but_an_imf_fixdate_is_refused() {
        for value in [
            "",
            "Sunday, 06-Nov-94 08:49:37 GMT", // RFC 850
            "Sun Nov  6 08:49:37 1994",       // asctime
            "Sun, 06 Nov 1994 08:49:37 UTC",
            "Sun, 06 Nov 1994 08:49 GMT",
            "Sun, 06 Foo 1994 08:49:37 GMT",
            "Sun, 32 Nov 1994 08:49:37 GMT",
            "Sun, 06 Nov 1994 24:00:00 GMT",
        ] {
            assert_eq!(parse_http_date(value), None, "{value:?}");
        }
    }

    #[test]
    fn a_date_written_for_a_test_mint_reads_back() {
        for secs in [0, 784_111_777, 1_835_481_599, device_now()] {
            assert_eq!(parse_http_date(&http_date(secs)), Some(secs), "{secs}");
        }
    }
}
