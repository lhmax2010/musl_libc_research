# FFmpeg RPM debuginfo-policy rerun checks

Formal command:

```text
scripts/build_gbs_ffmpeg.sh
```

Terminal build output:

```text
BUILD_GATE_PASS: ffmpeg F1/F2/F3 and size matrix passed
Wrote: /home/abuild/rpmbuild/RPMS/armv7l/ffmpeg-musl-demo-8.0.1-1.armv7l.rpm
BUILD_GBS_FFMPEG_PASS
```

RPM identity:

```text
rpm_sha256=daef87f36bdb6579db96eba4c570a893c9e3a6781508f7233e736274e3ef97da
```

`rpm -qlp results/rpms/ffmpeg-musl-demo-8.0.1-1.armv7l.rpm`:

```text
/opt/usr/ffmpeg-demo/bin/ffmpeg.F1
/opt/usr/ffmpeg-demo/bin/ffmpeg.F1.gc
/opt/usr/ffmpeg-demo/bin/ffmpeg.F2
/opt/usr/ffmpeg-demo/bin/ffmpeg.F2.gc
/opt/usr/ffmpeg-demo/bin/ffmpeg.F3
/opt/usr/ffmpeg-demo/bin/ffmpeg.F3.gc
/opt/usr/ffmpeg-demo/bin/timer
/opt/usr/ffmpeg-demo/share/artifacts.sha256
/opt/usr/ffmpeg-demo/share/c8-ledger.txt
/opt/usr/ffmpeg-demo/share/c8a-source-diff.txt
/opt/usr/ffmpeg-demo/share/compiler-decision-ffmpeg.txt
/opt/usr/ffmpeg-demo/share/configure-F1-baseline.txt
/opt/usr/ffmpeg-demo/share/configure-F1-gc.txt
/opt/usr/ffmpeg-demo/share/configure-F2-baseline.txt
/opt/usr/ffmpeg-demo/share/configure-F2-gc.txt
/opt/usr/ffmpeg-demo/share/configure-F3-baseline.txt
/opt/usr/ffmpeg-demo/share/configure-F3-gc.txt
/opt/usr/ffmpeg-demo/share/configure-equivalence.txt
/opt/usr/ffmpeg-demo/share/ffmpeg-configure-commands.txt
/opt/usr/ffmpeg-demo/share/ffmpeg.musl-mi.map
/opt/usr/ffmpeg-demo/share/function-surface.txt
/opt/usr/ffmpeg-demo/share/patch-consistency.txt
/opt/usr/ffmpeg-demo/share/sizes-matrix.txt
/opt/usr/ffmpeg-demo/share/tizen-ffmpeg-spec.orig
```

The sorted output above was diffed against the actual expansion of the two
spec `%files` globs from the successful payload. The diff was empty:

```text
RPM_FILELIST_EXPECTATION_GATE=PASS
RPM_FILELIST_DEBUG_PATH_GATE=PASS
```

The forbidden-path check was:

```text
rpm -qlp results/rpms/ffmpeg-musl-demo-8.0.1-1.armv7l.rpm |
grep -E '^/usr/(lib/debug|src/debug)(/|$)'
```

It produced no paths. The six files extracted from the RPM were compared to
`results/logs/ffmpeg-rpm-prechange-artifacts.sha256`; the diff was empty and
the extracted hashes were:

```text
beb3ec8005e0f27fcbc1dbecdcc2bdce0127e7781d4b04fa5dbbf8aa63b44690  ffmpeg.F1
5bb72fb6edb08d5583507d789d51b349d30c869f709c52e8ee768359ac96ff54  ffmpeg.F1.gc
a98cf4d04f664703acf6d8954e01d7156229563679c5cd944a14170f398391b1  ffmpeg.F2
095dad75b06aa94bd356c400c9fe639ef0e0db0bcb5e602fc864d623dc980514  ffmpeg.F2.gc
e848c7a05b6e53de0b84c7d2c6d1d6852ef336afb6cffce0c5eee17df5aa6df8  ffmpeg.F3
4f4fd18defa760ed71adc9b9b94d7fbec41e8addbc5636bed80f3f94db5ca5af  ffmpeg.F3.gc
RPM_BINARY_IDENTITY_GATE=PASS
```

Finally, `rpm -qp --requires` contained no `ShortCircuited` feature:

```text
RPM_SHORT_CIRCUIT_POISON_GATE=PASS
```
