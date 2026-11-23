//! Estimates written in a task's own text, for providers (or plans) without an estimate field.
//!
//! A word starting with `~` followed by minutes or hours: `~50`, `~50m`, `~1h`, `~1h30`, `~1h30m`.
//! Example: "Consegna Pcd ~1h30" is shown as "Consegna Pcd" with a 90-minute estimate.

/// The longest estimate we accept: one day. Anything above is more likely a typo.
const MAX_MIN: u32 = 24 * 60;

/// The estimate of the first tag in `text`, if any.
pub fn find(text: &str) -> Option<u32> {
    text.split_whitespace().find_map(tag_minutes)
}

/// `text` without its estimate tags (spacing between words is normalized to single spaces).
pub fn strip(text: &str) -> String {
    text.split_whitespace()
        .filter(|word| tag_minutes(word).is_none())
        .collect::<Vec<_>>()
        .join(" ")
}

/// Minutes for one word like `~1h30`, or `None` if the word isn't an estimate tag.
fn tag_minutes(word: &str) -> Option<u32> {
    let value = word.strip_prefix('~')?;
    let value = value.strip_suffix('m').unwrap_or(value);
    let minutes = match value.split_once('h') {
        None => value.parse::<u32>().ok()?,
        Some((hours, "")) => hours.parse::<u32>().ok()?.checked_mul(60)?,
        Some((hours, mins)) => hours
            .parse::<u32>()
            .ok()?
            .checked_mul(60)?
            .checked_add(mins.parse().ok()?)?,
    };
    (1..=MAX_MIN).contains(&minutes).then_some(minutes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_minutes_and_hours() {
        assert_eq!(find("Write report ~50"), Some(50));
        assert_eq!(find("Write report ~50m"), Some(50));
        assert_eq!(find("~1h Write report"), Some(60));
        assert_eq!(find("Write ~1h30 report"), Some(90));
        assert_eq!(find("Write report ~1h30m"), Some(90));
    }

    #[test]
    fn ignores_what_is_not_a_tag() {
        assert_eq!(find("Call Marco ~ tomorrow"), None);
        assert_eq!(find("Path ~/notes"), None);
        assert_eq!(find("~0"), None);
        assert_eq!(find("~25h"), None); // more than a day
        assert_eq!(find("~99999999999h"), None); // would overflow u32: no panic
        assert_eq!(find("v1h30 no tilde"), None);
    }

    #[test]
    fn strips_tags_from_the_title() {
        assert_eq!(strip("Consegna Pcd ~1h30"), "Consegna Pcd");
        assert_eq!(strip("~25 Email"), "Email");
        assert_eq!(strip("Path ~/notes"), "Path ~/notes");
    }
}
