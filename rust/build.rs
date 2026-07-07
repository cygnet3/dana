fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();

    // 16 KB page-size devices reject native libs built with 4 KB ELF alignment.
    // Only 64-bit Android ABIs are affected (arm64-v8a, x86_64).
    if target_os == "android" && matches!(target_arch.as_str(), "aarch64" | "x86_64") {
        println!("cargo:rustc-link-arg=-Wl,--hash-style=both");
        println!("cargo:rustc-link-arg=-Wl,-z,max-page-size=16384");
    }
}
