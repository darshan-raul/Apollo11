import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVICES = ('identity', 'flight', 'booking', 'search', 'notification', 'frontend')
PACKAGED_STAGES = (5, 6, 7)


class ImageContractTests(unittest.TestCase):
    """Stage 5-7 images ship through CI, so they must keep the Stage 4 hardening."""

    def dockerfile(self, stage, service):
        return (ROOT / f'stages/stage{stage}/code/{service}/Dockerfile').read_text()

    def test_images_run_as_numeric_non_root_user(self):
        for stage in PACKAGED_STAGES:
            for service in SERVICES:
                with self.subTest(stage=stage, service=service):
                    users = re.findall(r'^USER\s+(\S+)', self.dockerfile(stage, service), re.M)
                    self.assertTrue(users, 'Dockerfile has no USER instruction')
                    uid = users[-1].split(':')[0]
                    # runAsNonRoot can only verify a numeric UID.
                    self.assertRegex(uid, r'^[0-9]+$')
                    self.assertNotEqual(int(uid), 0)

    def test_build_context_is_filtered(self):
        for stage in PACKAGED_STAGES:
            for service in SERVICES:
                with self.subTest(stage=stage, service=service):
                    self.assertTrue((ROOT / f'stages/stage{stage}/code/{service}/.dockerignore').is_file())

    def test_frontend_build_is_reproducible(self):
        for stage in PACKAGED_STAGES:
            with self.subTest(stage=stage):
                frontend = ROOT / f'stages/stage{stage}/code/frontend'
                self.assertTrue((frontend / 'package-lock.json').is_file())
                self.assertIn('npm ci', self.dockerfile(stage, 'frontend'))


if __name__ == '__main__':
    unittest.main()
