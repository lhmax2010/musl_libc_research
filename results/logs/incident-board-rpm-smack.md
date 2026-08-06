# Incident: board RPM installation blocked by Smack policy setup

Date: 2026-08-06
Target: `192.168.108.25`

## Reached state

The GBS build and all build-time gates passed. The produced RPM has SHA-256
`ed42d8978ffd838fc59e4b02a6ab7b36c2825475cd3be434ed952c5341f2fcfa`.
Before contacting the board, `scripts/deploy.sh` extracted the RPM and verified
all five payload hashes successfully. The board was already connected, root
mode was requested, and the RPM push completed.

## Complete installation error

After the RPM progress output, the complete error text was:

```text
No manifest in this package. Creating default one
error: Can't write smack rules
error: Setting up smack rules for musl-libc-demo failed
error: Plugin msm: hook psm_pre failed
warning: Plugin msm: hook psm_post failed
error: musl-libc-demo-1.0.0-1.armv7l: install failed
error: Unable to write device security policy to /etc/device-sec-policy
```

The full raw deployment output, including RPM progress, is preserved in
`results/logs/deploy.log`.

## Required read-only diagnostics

`ls -Z /opt/usr` returned:

```text
                _ apps                        _ home
                _ data                        _ media
                _ dbspace     User::App::Shared media_shared
                _ dotnet                      _ share
       User::Home globalapps
```

The relevant mounts are writable:

```text
/dev/mmcblk0p3 on /opt type ext4 (rw,relatime)
/dev/mmcblk0p5 on /opt/usr type f2fs (rw,relatime,lazytime,...)
```

`rpm -q musl-libc-demo` confirmed:

```text
package musl-libc-demo is not installed
```

The exact full mount lines and command outputs are retained in
`results/logs/board-install-diagnostics.log`.

## Disposition

The `sdb shell` transport returned success despite the remote `rpm` errors, so
the deploy script continued until the board-hash comparison failed because
`/opt/usr/musl-demo` did not exist. Its final exit code was 5. This observation
does not change the root failure: RPM installation did not complete.

Per the pre-authorized parking rule, no manual file copy, RPM workaround,
Smack-policy mutation, deploy-script fix, smoke test, `run_board`, or report
generation was attempted. Further work awaits explicit authorization.
