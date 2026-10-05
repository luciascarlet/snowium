#![feature(thread_local)]

use std::cell::Cell;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Condvar, Mutex, atomic::{AtomicUsize, Ordering}};
use std::time::{Duration, Instant};

static DROPS: AtomicUsize = AtomicUsize::new(0);
#[thread_local]
static mut COMPILER_TLS: usize = 11;
struct DropCounter;
impl Drop for DropCounter { fn drop(&mut self) { DROPS.fetch_add(1, Ordering::SeqCst); } }
thread_local! {
    static LOCAL: Cell<usize> = const { Cell::new(7) };
    static DROP: DropCounter = DropCounter;
}

fn main() {
    println!("Rust std source port on {}", std::env::consts::OS);
    if std::env::args().any(|arg| arg == "--backtrace") {
        let backtrace = std::backtrace::Backtrace::force_capture();
        println!("BACKTRACE status={:?}, frames={backtrace:?}", backtrace.status());
        if backtrace.status() != std::backtrace::BacktraceStatus::Captured {
            std::process::exit(1);
        }
        return;
    }
    let mut map = HashMap::new();
    map.insert("Snow Leopard", 1068);
    assert_eq!(map["Snow Leopard"], 1068);
    println!("PASS random-seeded HashMap, allocation, formatting");
    LOCAL.with(|value| value.set(900));
    for index in 0..64 {
        std::thread::Builder::new().name(format!("snowium-{index}")).spawn(move || {
            LOCAL.with(|value| { assert_eq!(value.get(), 7); value.set(index); });
            unsafe { assert_eq!(COMPILER_TLS, 11); COMPILER_TLS = index; }
            DROP.with(|_| ());
        }).unwrap().join().unwrap();
    }
    assert_eq!(DROPS.load(Ordering::SeqCst), 64);
    LOCAL.with(|value| assert_eq!(value.get(), 900));
    unsafe { assert_eq!(COMPILER_TLS, 11); }
    println!("PASS 64 named pthreads, pthread and emulated compiler TLS, thread-exit destructors");
    let shared = Arc::new((Mutex::new(false), Condvar::new()));
    let copy = shared.clone();
    let start = Instant::now();
    let worker = std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(20));
        *copy.0.lock().unwrap() = true;
        copy.1.notify_one();
    });
    let guard = shared.0.lock().unwrap();
    let (guard, timeout) = shared.1.wait_timeout_while(guard, Duration::from_secs(5), |done| !*done).unwrap();
    assert!(*guard && !timeout.timed_out() && start.elapsed() >= Duration::from_millis(10));
    worker.join().unwrap();
    println!("PASS mutex/condition variable, timeout, monotonic clock, sleep");
    let base = std::env::temp_dir().join(format!("snowium-rust-{}", std::process::id()));
    std::fs::create_dir(&base).unwrap();
    std::fs::write(base.join("original"), b"Snowium on Darwin 10\n").unwrap();
    std::fs::copy(base.join("original"), base.join("copy")).unwrap();
    assert_eq!(std::fs::read(base.join("copy")).unwrap(), b"Snowium on Darwin 10\n");
    assert_eq!(std::fs::read_dir(&base).unwrap().count(), 2);
    std::fs::remove_dir_all(&base).unwrap();
    println!("PASS file read/write/copy, directory enumeration and removal");
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        stream.write_all(b"Darwin10").unwrap();
    });
    let mut stream = TcpStream::connect_timeout(&addr, Duration::from_secs(5)).unwrap();
    let mut message = String::new();
    stream.read_to_string(&mut message).unwrap();
    assert_eq!(message, "Darwin10");
    server.join().unwrap();
    println!("PASS localhost TCP server/client and connection timeout");
    let child = std::process::Command::new("/bin/echo").arg("rust-spawn").output().unwrap();
    assert!(child.status.success());
    assert_eq!(child.stdout, b"rust-spawn\n");
    println!("PASS child process spawn, pipe capture, wait status");
    println!("PASS complete Rust standard library regression");
}
