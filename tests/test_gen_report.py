import unittest
from pathlib import Path

from scripts.gen_report import parse_malloc_samples


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
