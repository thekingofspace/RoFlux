use std::io::IsTerminal;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Once;

static QUIET: AtomicBool = AtomicBool::new(false);
static COLOR: AtomicBool = AtomicBool::new(false);
static READY: Once = Once::new();

#[cfg(windows)]
fn enable_ansi() -> bool {
    use windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE;
    use windows_sys::Win32::System::Console::{
        GetConsoleMode, GetStdHandle, SetConsoleMode, ENABLE_VIRTUAL_TERMINAL_PROCESSING,
        STD_ERROR_HANDLE,
    };

    unsafe {
        let handle = GetStdHandle(STD_ERROR_HANDLE);

        if handle.is_null() || handle == INVALID_HANDLE_VALUE {
            return false;
        }

        let mut mode = 0;

        if GetConsoleMode(handle, &mut mode) == 0 {
            return false;
        }

        if mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING != 0 {
            return true;
        }

        SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0
    }
}

#[cfg(not(windows))]
fn enable_ansi() -> bool {
    std::env::var("TERM").map(|value| value != "dumb").unwrap_or(false)
}

fn prepare() {
    READY.call_once(|| {
        let wanted = std::env::var_os("NO_COLOR").is_none() && std::io::stderr().is_terminal();

        COLOR.store(wanted && enable_ansi(), Ordering::Relaxed);
    });
}

pub fn set_quiet(value: bool) {
    QUIET.store(value, Ordering::Relaxed);
}

fn quiet() -> bool {
    QUIET.load(Ordering::Relaxed)
}

fn emit(tag: &str, color: &str, message: &str) {
    if quiet() {
        return;
    }

    prepare();

    if COLOR.load(Ordering::Relaxed) {
        eprintln!("\x1b[{color}m{tag:>7}\x1b[0m {message}");
    } else {
        eprintln!("{tag:>7} {message}");
    }
}

pub fn info(message: impl AsRef<str>) {
    emit("info", "36", message.as_ref());
}

pub fn good(message: impl AsRef<str>) {
    emit("ok", "32", message.as_ref());
}

pub fn warn(message: impl AsRef<str>) {
    emit("warn", "33", message.as_ref());
}

pub fn fail(message: impl AsRef<str>) {
    emit("error", "31", message.as_ref());
}

pub fn hook(message: impl AsRef<str>) {
    emit("hook", "35", message.as_ref());
}

pub fn detail(message: impl AsRef<str>) {
    emit("", "90", message.as_ref());
}

pub fn sync(message: impl AsRef<str>) {
    emit("sync", "34", message.as_ref());
}
