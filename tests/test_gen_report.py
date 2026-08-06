import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

from scripts.gen_report import main_mimalloc, parse_malloc_samples, parse_metric_samples


ROOT = Path(__file__).resolve().parents[1]


class MallocParserTests(unittest.TestCase):
    def test_current_results_resynchronizes_one_invalid_sample(self) -> None:
        text = (ROOT / "results/results.txt").read_text(encoding="utf-8")
        samples = parse_malloc_samples(text, "results.txt")
        valid = [sample for sample in samples if sample.valid]
        invalid = [sample for sample in samples if not sample.valid]

        self.assertEqual(30, len(samples))
        self.assertEqual(29, len(valid))
        self.assertEqual(1, len(invalid))
        self.assertEqual("musl-dyn", invalid[0].variant)
        self.assertEqual(2, invalid[0].rep)
        self.assertEqual(4, invalid[0].threads)

        recovered = next(
            sample
            for sample in valid
            if sample.variant == "musl-static"
            and sample.rep == 3
            and sample.threads == 1
        )
        self.assertEqual("310.7", recovered.values["ns_per_op_mean"])

        counts = {
            (variant, threads): sum(
                sample.valid
                and sample.variant == variant
                and sample.threads == threads
                for sample in samples
            )
            for variant in ("glibc-dyn", "musl-static", "musl-dyn")
            for threads in (1, 4)
        }
        self.assertEqual(
            {
                ("glibc-dyn", 1): 5,
                ("glibc-dyn", 4): 5,
                ("musl-static", 1): 5,
                ("musl-static", 4): 5,
                ("musl-dyn", 1): 5,
                ("musl-dyn", 4): 4,
            },
            counts,
        )

    def test_mimalloc_report_parses_four_variant_session(self) -> None:
        text = """measurement.sample_sentinel=required
### sizes
-rwxr-xr-x 1 root root 400 Aug 6 00:00 /opt/usr/musl-demo/bin/micro.musl-static
-rwxr-xr-x 1 root root 600 Aug 6 00:00 /opt/usr/musl-demo/bin/micro.musl-mi
### startup quad
startup_quad,1,1000000,800000,900000,700000
startup_valid,1
### mem smaps_rollup x3
memcfg=musl-static,rep=1
mem.pid=10
Rss: 52 kB
Pss: 50 kB
Private_Clean: 42 kB
Private_Dirty: 8 kB
sample_end=OK
memcfg=musl-mi,rep=1
mem.pid=11
Rss: 100 kB
Pss: 90 kB
Private_Clean: 60 kB
Private_Dirty: 30 kB
sample_end=OK
### threads 200
threadscfg=musl-static
threads.requested=200
threads.created=200
status.VmSize: 28000 kB
status.VmRSS: 800 kB
status.VmData: 26000 kB
status.Threads: 201
sample_end=OK
threadscfg=musl-mi
threads.requested=200
threads.created=200
status.VmSize: 30000 kB
status.VmRSS: 900 kB
status.VmData: 28000 kB
status.Threads: 201
sample_end=OK
### malloc churn
malloccfg=glibc-dyn,rep=1,threads=1
malloc.threads=1
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=100.0
malloc.checksum=a
sample_end=OK
malloccfg=musl-static,rep=1,threads=1
malloc.threads=1
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=200.0
malloc.checksum=a
sample_end=OK
malloccfg=musl-dyn,rep=1,threads=1
malloc.threads=1
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=210.0
malloc.checksum=a
sample_end=OK
malloccfg=musl-mi,rep=1,threads=1
malloc.threads=1
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=80.0
malloc.checksum=a
sample_end=OK
malloccfg=glibc-dyn,rep=1,threads=4
malloc.threads=4
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=150.0
malloc.checksum=a
sample_end=OK
malloccfg=musl-static,rep=1,threads=4
malloc.threads=4
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=900.0
malloc.checksum=a
sample_end=OK
malloccfg=musl-dyn,rep=1,threads=4
malloc.threads=4
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=910.0
malloc.checksum=a
sample_end=OK
malloccfg=musl-mi,rep=1,threads=4
malloc.threads=4
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=120.0
malloc.checksum=a
sample_end=OK
"""
        mem = parse_metric_samples(text, "mem")
        threads = parse_metric_samples(text, "threads")
        self.assertEqual(2, len(mem))
        self.assertTrue(all(sample.valid for sample in mem))
        self.assertEqual(2, len(threads))
        self.assertTrue(all(sample.valid for sample in threads))

        output = StringIO()
        with redirect_stdout(output):
            rc = main_mimalloc(
                Path("results/results-mimalloc.txt"),
                Path("results/logs/compiler-decision-mimalloc.txt"),
                text,
            )
        report = output.getvalue()
        self.assertEqual(0, rc)
        self.assertIn("musl-mi median：**0.700 ms**", report)
        self.assertIn("120.0 (n=1)", report)
        self.assertIn("| Private_Dirty | 8 kB | 30 kB | 22 kB | 3.75x |", report)
        self.assertIn("VmSize +2000 KB", report)
        self.assertIn("二进制 +0.2 KB", report)

    def test_sentinel_required_dataset_rejects_missing_sentinel(self) -> None:
        text = """measurement.sample_sentinel=required
malloccfg=glibc-dyn,rep=1,threads=4
malloc.threads=4
malloc.iters_per_thread=10
malloc.ns_per_op_mean=1.0
malloc.checksum=abc
malloccfg=musl-static,rep=1,threads=4
malloc.threads=4
malloc.iters_per_thread=10
malloc.ns_per_op_mean=2.0
malloc.checksum=def
sample_end=OK
"""
        samples = parse_malloc_samples(text, "sentinel.txt")
        self.assertEqual(2, len(samples))
        self.assertFalse(samples[0].valid)
        self.assertIn("missing=sample_end=OK", samples[0].invalid_reasons)
        self.assertTrue(samples[1].valid)

    def test_primary_plus_supplement_have_expected_cell_counts(self) -> None:
        samples = []
        for name in ("results.txt", "results-supplement.txt"):
            path = ROOT / "results" / name
            samples.extend(parse_malloc_samples(path.read_text(encoding="utf-8"), name))

        valid = [sample for sample in samples if sample.valid]
        invalid = [sample for sample in samples if not sample.valid]
        counts = {
            (variant, threads): sum(
                sample.variant == variant and sample.threads == threads
                for sample in valid
            )
            for variant in ("glibc-dyn", "musl-static", "musl-dyn")
            for threads in (1, 4)
        }

        self.assertEqual(32, len(valid))
        self.assertEqual(1, len(invalid))
        self.assertEqual(
            {
                ("glibc-dyn", 1): 5,
                ("glibc-dyn", 4): 6,
                ("musl-static", 1): 5,
                ("musl-static", 4): 6,
                ("musl-dyn", 1): 5,
                ("musl-dyn", 4): 5,
            },
            counts,
        )


if __name__ == "__main__":
    unittest.main()
