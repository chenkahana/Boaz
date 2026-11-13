use adblock::{
    Engine,
    lists::{FilterSet, ParseOptions, parse_filter},
    request::Request,
    resources::{InMemoryResourceStorage, Resource},
};
use serde_json::{Value, json};
use std::{
    collections::HashSet,
    panic::{AssertUnwindSafe, catch_unwind},
    ptr, slice,
};

const INPUT: usize = 64 * 1024 * 1024;
const QUERY: usize = 64 * 1024;
const OUTPUT: usize = 128 * 1024 * 1024;
const INVALID: i32 = 1;
const LARGE: i32 = 2;
const PANIC: i32 = 3;
const REJECTED: i32 = 4;

#[repr(C)]
pub struct Bytes {
    pub data: *const u8,
    pub len: usize,
}
#[repr(C)]
pub struct Buffer {
    pub data: *mut u8,
    pub len: usize,
}
pub struct Snapshot(Engine);

fn boundary(f: impl FnOnce() -> Result<(), i32>) -> i32 {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => e,
        Err(_) => PANIC,
    }
}
unsafe fn bytes<'a>(b: Bytes, limit: usize) -> Result<&'a [u8], i32> {
    if b.len > limit {
        return Err(LARGE);
    }
    if b.len == 0 {
        return Ok(&[]);
    }
    if b.data.is_null() {
        return Err(INVALID);
    }
    Ok(unsafe { slice::from_raw_parts(b.data, b.len) })
}
unsafe fn text<'a>(b: Bytes, limit: usize) -> Result<&'a str, i32> {
    std::str::from_utf8(unsafe { bytes(b, limit)? }).map_err(|_| INVALID)
}
unsafe fn output(out: *mut Buffer) -> Result<(), i32> {
    if out.is_null() {
        return Err(INVALID);
    }
    unsafe {
        out.write(Buffer {
            data: ptr::null_mut(),
            len: 0,
        });
    }
    Ok(())
}
unsafe fn emit(out: *mut Buffer, value: Vec<u8>) -> Result<(), i32> {
    if value.len() > OUTPUT {
        return Err(LARGE);
    }
    let mut value = value.into_boxed_slice();
    unsafe {
        out.write(Buffer {
            data: value.as_mut_ptr(),
            len: value.len(),
        });
    }
    std::mem::forget(value);
    Ok(())
}
fn json_bytes(value: Value) -> Result<Vec<u8>, i32> {
    serde_json::to_vec(&value).map_err(|_| INVALID)
}
unsafe fn engine<'a>(p: *const Snapshot) -> Result<&'a Engine, i32> {
    unsafe { p.as_ref() }.map(|p| &p.0).ok_or(INVALID)
}
fn send_sync<T: Send + Sync>() {}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn boaz_adblock_create(
    rules: Bytes,
    resources: Bytes,
    out: *mut *mut Snapshot,
    diagnostics: *mut Buffer,
) -> i32 {
    boundary(|| {
        if out.is_null() {
            return Err(INVALID);
        }
        unsafe {
            out.write(ptr::null_mut());
            output(diagnostics)?;
        }
        send_sync::<Engine>();
        let rules = unsafe { text(rules, INPUT)? };
        let resources: Vec<Resource> =
            serde_json::from_slice(unsafe { bytes(resources, INPUT)? }).map_err(|_| INVALID)?;
        let mut storage = InMemoryResourceStorage::default();
        let mut resource_errors = Vec::new();
        let mut resource_error_count = 0usize;
        for (index, resource) in resources.into_iter().enumerate() {
            if storage.add_resource(resource).is_err() {
                resource_error_count += 1;
                if resource_errors.len() < 32 {
                    resource_errors.push(index);
                }
            }
        }
        let mut rejected = 0usize;
        let mut invalid = Vec::new();
        for (index, line) in rules.lines().enumerate() {
            let line = line.trim();
            if line.is_empty()
                || line.starts_with('!')
                || line.starts_with("[Adblock")
                || line == "#"
                || line
                    .strip_prefix('#')
                    .is_some_and(|s| s.starts_with(char::is_whitespace))
            {
                continue;
            }
            if parse_filter(line, false, ParseOptions::default()).is_err() {
                rejected += 1;
                if invalid.len() < 32 {
                    invalid.push(index + 1);
                }
            }
        }
        unsafe {
            emit(
                diagnostics,
                json_bytes(json!({"rejected_rules": rejected,
            "invalid_rule_line_numbers_sample": invalid, "rejected_resources": resource_error_count,
            "invalid_resource_indices_sample": resource_errors}))?,
            )?;
        }
        if rejected != 0 || resource_error_count != 0 {
            return Err(REJECTED);
        }
        let mut set = FilterSet::new(false);
        set.add_filter_list(rules.to_owned(), ParseOptions::default());
        let mut engine = Engine::new_with_filter_set(set);
        engine.use_resource_storage(storage);
        unsafe {
            out.write(Box::into_raw(Box::new(Snapshot(engine))));
        }
        Ok(())
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn boaz_adblock_network(
    p: *const Snapshot,
    url: Bytes,
    source: Bytes,
    kind: Bytes,
    method: Bytes,
    out: *mut Buffer,
) -> i32 {
    boundary(|| unsafe {
        output(out)?;
        let request = Request::new(
            text(url, QUERY)?,
            text(source, QUERY)?,
            text(kind, 64)?,
            text(method, 32)?,
        )
        .map_err(|_| INVALID)?;
        let result = engine(p)?.check_network_request(&request);
        emit(
            out,
            json_bytes(json!({"should_block": result.should_block(), "result": result}))?,
        )
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn boaz_adblock_cosmetics(
    p: *const Snapshot,
    url: Bytes,
    out: *mut Buffer,
) -> i32 {
    boundary(|| unsafe {
        output(out)?;
        let result = engine(p)?.url_cosmetic_resources(text(url, QUERY)?);
        emit(out, serde_json::to_vec(&result).map_err(|_| INVALID)?)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn boaz_adblock_selectors(
    p: *const Snapshot,
    input: Bytes,
    out: *mut Buffer,
) -> i32 {
    boundary(|| unsafe {
        output(out)?;
        let value: Value = serde_json::from_slice(bytes(input, QUERY)?).map_err(|_| INVALID)?;
        let strings = |name: &str| -> Result<Vec<String>, i32> {
            value
                .get(name)
                .and_then(Value::as_array)
                .ok_or(INVALID)?
                .iter()
                .map(|v| v.as_str().map(str::to_owned).ok_or(INVALID))
                .collect()
        };
        let classes = strings("classes")?;
        let ids = strings("ids")?;
        let exceptions: HashSet<String> = strings("exceptions")?.into_iter().collect();
        let result = engine(p)?.hidden_class_id_selectors(classes, ids, &exceptions);
        emit(out, serde_json::to_vec(&result).map_err(|_| INVALID)?)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn boaz_adblock_serialize(p: *const Snapshot, out: *mut Buffer) -> i32 {
    boundary(|| unsafe {
        output(out)?;
        emit(out, engine(p)?.serialize())
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn boaz_adblock_buffer_free(buffer: Buffer) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !buffer.data.is_null() {
            unsafe {
                drop(Box::from_raw(ptr::slice_from_raw_parts_mut(
                    buffer.data,
                    buffer.len,
                )));
            }
        }
    }));
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn boaz_adblock_destroy(p: *mut Snapshot) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !p.is_null() {
            unsafe {
                drop(Box::from_raw(p));
            }
        }
    }));
}
