//! Random device keys and pairing codes, and hashing.

use sha2::{Digest, Sha256};

/// Letters and digits that can't be confused with each other when read aloud or off a watch
/// (no 0/O, 1/I/L).
const CODE_ALPHABET: &[u8] = b"23456789ABCDEFGHJKMNPQRSTUVWXYZ";

fn random_bytes<const N: usize>() -> [u8; N] {
    let mut bytes = [0u8; N];
    // Fails only if the runtime has no crypto.getRandomValues(), which Workers always has.
    getrandom::getrandom(&mut bytes).expect("crypto.getRandomValues is available");
    bytes
}

/// A secret the watch keeps and sends as `X-Api-Key`: 32 random bytes as hex.
pub fn device_key() -> String {
    hex(&random_bytes::<32>())
}

/// A one-time value: the OAuth `state` and the cookie that goes with it.
pub fn nonce() -> String {
    hex(&random_bytes::<16>())
}

/// Our own user ids.
pub fn user_id() -> String {
    hex(&random_bytes::<12>())
}

/// An 8-character pairing code like "K7F2QM9X".
pub fn pairing_code() -> String {
    code_from(|| random_bytes::<1>()[0], 8)
}

/// Builds a code from random bytes. Bytes at or above the largest multiple of the alphabet size
/// are skipped (rejection sampling): taking `byte % 31` directly would make the first letters a
/// little more likely than the others.
fn code_from(mut next_byte: impl FnMut() -> u8, len: usize) -> String {
    let n = CODE_ALPHABET.len() as u8;
    let limit = 256 / n as u16 * n as u16; // 248 for 31 letters
    let mut code = String::with_capacity(len);
    while code.len() < len {
        let b = next_byte();
        if (b as u16) < limit {
            code.push(CODE_ALPHABET[(b % n) as usize] as char);
        }
    }
    code
}

/// We store only the SHA-256 of device keys: a leaked database doesn't give working keys.
pub fn hash(key: &str) -> String {
    hex(&Sha256::digest(key.as_bytes()))
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Compares two secrets in time that doesn't depend on where they first differ,
/// so response timing can't be used to guess a key one character at a time.
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_use_the_alphabet_and_skip_biased_bytes() {
        // 255 and 248 are above the limit and must be skipped; 0 -> '2', 31 -> '2', 30 -> 'Z'.
        let mut bytes = [255u8, 0, 248, 31, 30].into_iter();
        let code = code_from(|| bytes.next().unwrap(), 3);
        assert_eq!(code, "22Z");
    }

    #[test]
    fn hashes_are_hex_sha256() {
        assert_eq!(
            hash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn key_comparison() {
        assert!(constant_time_eq(b"s3cret", b"s3cret"));
        assert!(!constant_time_eq(b"s3cret", b"s3creT"));
        assert!(!constant_time_eq(b"s3cret", b"s3cre"));
    }
}
