# Incident: board test clip is not decodable by the frozen H.264 island

Status: **PARKED — replacement H.264 material or an explicit scope ruling is required**

## Stopping point

The release-1 RPM was installed on `192.168.108.26` with
`rpm -Uvh --noplugins --force`. Host/RPM/board payload hashes matched, the
single `/root` media candidate was copied to the private data directory with
its frozen SHA-256 intact, and the F3 mimalloc runtime banner produced one
positive plus two negative controls. No board measurement was started.

The only media candidate permitted by the selection rule was:

```text
/root/64687_VID_BM_MM_h265_fhd_seamless.mp4
sha256=551e80dfa22fe1feccb1249a2dd924430fc48821272dd2f6ad6cad1fdffac2aa
size=59938456 bytes
```

## Failure

The H.264-only F1 smoke reported the MP4 video sample entry as `hev1` and
could not decode it:

```text
Stream #0:0[0x1](und): Video: h264 (hev1 / 0x31766568), none, 720x480
Invalid NAL unit size (0 > 170641).
Error splitting the input into NAL units.
Error processing packet in decoder: Invalid data found when processing input
Nothing was written into output file, because at least one of its streams received no packets.
frame=    0
Conversion failed!
CONFIRM_REMOTE_RC=183
```

`hev1` is the HEVC-in-MP4 sample entry. The forced native H.264 decoder sees
HEVC packet data, so the invalid NAL errors and zero output frames are
consistent with a codec mismatch. This contradicts the prompt's statement
that the preloaded PerfHotSpotAnalyzer material is an H.264 sample.

## Fail-closed correction

The first deployment-script version streamed the remote FFmpeg output through
`sdb shell` but did not embed and parse the remote command's exit status. It
also did not require an output frame, so the visible decode errors were
followed by an incorrect local `gate.smoke.*=PASS` and terminal
`DEPLOY_FFMPEG_PASS`. That output is retained verbatim as
`results/logs/deploy-ffmpeg-initial-false-positive.log`; it is not accepted as
a valid gate result.

The smoke gate has been hardened to use `-xerror`, explicitly select only the
video stream (`-map 0:v:0 -an`), return `smoke_remote_rc` in-band, require a
zero remote status, and require `frame=1`. The independent confirmation output
is archived in `results/logs/ffmpeg-clip-codec-confirmation.log`.

The corrected deployment run stopped locally with exit status 6 at the first
variant, as required:

```text
smoke_remote_rc=183
DEPLOY_FAIL F1 h264 smoke remote_rc=183
```

Evidence hashes:

```text
8ce5d41718a7fe627542303473c4e1863248cb1d117f804f391c836024c025e9  results/logs/deploy-ffmpeg-initial-false-positive.log
d6dcb109338c2dd7213e876e4a5f8e707699a366c288ca67423a939de48aea5a  results/logs/ffmpeg-clip-codec-confirmation.log
772089bad158b237e47e96e6f0deb96c88d79b82e0dbcbcfb00e0c28c8219c78  results/logs/deploy-ffmpeg.log
```

## Boundary and next action

Changing the island decoder to HEVC, transcoding the supplied material,
selecting a non-existent alternative, or fetching a new clip would change the
frozen experiment input or scope and is not pre-authorized. The board needs
exactly one valid H.264 `.mp4`, `.h264`, or `.mkv` candidate under `/root`,
followed by a new first-use SHA-256 ruling. Until then:

```text
deployment_smoke=FAIL
board_measurement=NOT_RUN
results/results-ffmpeg.txt=NOT_CREATED
results/report-ffmpeg.md=NOT_CREATED
```

Resume command after the material and frozen hash are explicitly updated:

```text
SDB_TARGET=192.168.108.26 scripts/deploy_ffmpeg.sh
```
