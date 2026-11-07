# Third-party licenses

Celerite itself is licensed under the MIT license (see `LICENSE`).

The platform gems bundle the non-system shared libraries the native binary
links against, so the gem runs without Homebrew, MSYS2, or extra system
packages. The corresponding license texts are shipped in `assets/licenses/`:

| Library | License | Text | Bundled on |
|---|---|---|---|
| Boehm-Demers-Weiser GC (`libgc`) | MIT-style | `assets/licenses/bdw-gc.txt` | macOS, Windows |
| OpenSSL 3/4 (`libssl`, `libcrypto`) | Apache-2.0 | `assets/licenses/openssl.txt` | macOS arm64, Linux, Windows |
| OpenSSL 1.1 (`libssl`, `libcrypto`) | OpenSSL/SSLeay | `assets/licenses/openssl-1.1.txt` | macOS x86_64 |
| PCRE2 (`libpcre2-8`) | BSD-3-Clause WITH PCRE2-exception | `assets/licenses/pcre2.txt` | macOS, Linux, Windows |
| libyaml (`libyaml`) | MIT | `assets/licenses/libyaml.txt` | macOS, Linux, Windows |
| zlib (`libz`) | zlib | `assets/licenses/zlib.txt` | Linux, Windows |
| zstd (`libzstd`) | BSD-3-Clause | `assets/licenses/zstd.txt` | Linux |
| libiconv (`iconv-2.dll`) | LGPL-2.1 | `assets/licenses/libiconv.txt` | Windows |

System libraries are not redistributed: macOS `libSystem`, `libz`, `libiconv`;
Linux glibc, `ld-linux`, and `libgcc_s`; Windows system DLLs and the Microsoft
VC++ runtime.

`iconv-2.dll` is dynamically linked and shipped as a separate library, so it
can be replaced by the user. libiconv source: https://www.gnu.org/software/libiconv/
