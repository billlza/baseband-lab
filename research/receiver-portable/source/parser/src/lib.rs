// SPDX-License-Identifier: GPL-3.0-or-later
//! The host passes one bounded response. Only Mooring's existing radio CSV can be returned.
use mooring_daemon_core::{
    RadioSample, radio_table,
    router::{RouterUnavailableReason, netgear::parse_netgear_model_json},
};
use mooring_model::UnixTime;
use std::cell::RefCell;

const LIMIT: usize = 1 << 20;
thread_local! {
    static INPUT: RefCell<Vec<u8>> = RefCell::new(vec![0; LIMIT]);
    static OUTPUT: RefCell<String> = const { RefCell::new(String::new()) };
}

#[unsafe(no_mangle)]
pub extern "C" fn input_capacity() -> usize {
    LIMIT
}

#[unsafe(no_mangle)]
pub extern "C" fn input_address() -> *mut u8 {
    INPUT.with_borrow_mut(|buffer| buffer.as_mut_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn output_address() -> *const u8 {
    OUTPUT.with_borrow(|s| s.as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn output_length() -> usize {
    OUTPUT.with_borrow(String::len)
}

/// Source kinds: 0 = document, 1 = unreachable, 2 = expired session, 3 = invalid reply, 4 = local failure.
/// The clock is the observing host's UTC seconds. JS supplies an exactly representable BigInt.
#[unsafe(no_mangle)]
pub extern "C" fn sample(length: usize, kind: u32, seconds: u64) -> u32 {
    OUTPUT.with_borrow_mut(String::clear);
    if length > LIMIT || (kind != 0 && length != 0) {
        return 1;
    }
    let at = UnixTime::from_secs(seconds);
    let row = match kind {
        0 => INPUT.with_borrow_mut(|buf| {
            let parsed = parse_netgear_model_json(&buf[..length]);
            buf[..length].fill(0);
            RadioSample::of(at, parsed.as_ref().map_err(|err| err.reason()))
        }),
        1 => RadioSample::of(at, Err(RouterUnavailableReason::Unreachable)),
        2 => RadioSample::of(at, Err(RouterUnavailableReason::AuthFailed)),
        3 => RadioSample::of(at, Err(RouterUnavailableReason::Malformed)),
        4 => RadioSample::of(at, Err(RouterUnavailableReason::LocalFailure)),
        _ => return 1,
    };
    match radio_table::samples_table(&[row]) {
        Ok(csv) => {
            OUTPUT.with_borrow_mut(|out| *out = csv);
            0
        }
        Err(_) => 2,
    }
}
