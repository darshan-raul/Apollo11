"""Check packaging contracts without contacting Kubernetes."""
from pathlib import Path
import importlib.util
import subprocess
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]
APP_SAS = {'identity', 'flight', 'booking', 'search', 'notification', 'frontend',
           'identity-db', 'flight-db', 'booking-db', 'redis',
           'init-identity-db', 'init-flight-db', 'init-booking-db'}


def render(stage, env='dev', mode='helm', extra=()):
    if mode == 'helm':
        cmd = ['helm', 'template', 'apollo11', f'stages/stage{stage}/helm/apollo11',
               '-f', f'stages/stage{stage}/helm/apollo11/values-{env}.yaml',
               '--set', 'gateway.envoy.bundleInstall=false', '--set', 'metallb.bundleInstall=false', *extra]
    else:
        cmd = ['kubectl', 'kustomize', f'stages/stage{stage}/overlays/{env}']
    return subprocess.check_output(cmd, cwd=ROOT, text=True)


class RenderTests(unittest.TestCase):
    def test_all_packaging_environments_preserve_security_and_tls_contract(self):
        for stage in (5, 6, 7):
            for env in ('dev', 'staging', 'prod'):
                for mode in ('helm', 'kustomize'):
                    with self.subTest(stage=stage, env=env, mode=mode):
                        docs = [d for d in yaml.safe_load_all(render(stage, env, mode)) if d]
                        self.assertFalse(any(d.get('type') == 'kubernetes.io/tls' for d in docs))
                        accounts = [d for d in docs if d['kind'] == 'ServiceAccount' and d['metadata']['name'] in APP_SAS]
                        self.assertEqual({d['metadata']['name'] for d in accounts}, APP_SAS)
                        self.assertTrue(all(d.get('automountServiceAccountToken') is False for d in accounts))
                        gateway = next(d for d in docs if d['kind'] == 'Gateway')
                        listener = next(l for l in gateway['spec']['listeners'] if l['protocol'] == 'HTTPS')
                        self.assertEqual(listener['tls']['certificateRefs'][0]['name'], 'apollo-edge-tls')
                        if stage == 7:
                            search = next(d for d in docs if d['kind'] == 'Deployment' and d['metadata']['name'] == 'search')
                            envs = search['spec']['template']['spec']['containers'][0]['env']
                            self.assertEqual(next(e['value'] for e in envs if e['name'] == 'CACHE_ENABLED'), 'true')

    def test_disabled_tls_has_no_dangling_https_listener(self):
        for stage in (5, 6, 7):
            docs = [d for d in yaml.safe_load_all(render(stage, extra=('--set', 'gateway.tls.enabled=false'))) if d]
            gateway = next(d for d in docs if d['kind'] == 'Gateway')
            self.assertEqual([l['protocol'] for l in gateway['spec']['listeners']], ['HTTP'])

    def test_helm_renders_are_deterministic(self):
        for stage in (5, 6, 7):
            self.assertEqual(render(stage), render(stage))

    def test_cache_baseline_flag_reaches_search_container(self):
        docs = [d for d in yaml.safe_load_all(render(7, extra=('--set', 'apps.search.cacheEnabled=false'))) if d]
        search = next(d for d in docs if d['kind'] == 'Deployment' and d['metadata']['name'] == 'search')
        envs = search['spec']['template']['spec']['containers'][0]['env']
        self.assertEqual(next(e['value'] for e in envs if e['name'] == 'CACHE_ENABLED'), 'false')

    def test_signal_progression_and_baseline_exclusion(self):
        spec = importlib.util.spec_from_file_location('signals', ROOT / 'stages/stage6/scripts/select-signals.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for mode in ('helm', 'kustomize'):
            text = render(6, mode=mode)
            baseline = [d for d in yaml.safe_load_all(module.select(text, 6, baseline=True)) if d]
            self.assertFalse(any(d['metadata'].get('namespace') == 'apollo-observability' or
                                 d['metadata']['name'] == 'apollo-observability' for d in baseline))
            previous = set()
            for stage in range(1, 7):
                selected = [d for d in yaml.safe_load_all(module.select(text, stage)) if d]
                names = {d['metadata']['name'] for d in selected}
                self.assertTrue(previous <= names)
                self.assertEqual('grafana' in names, stage >= 2)
                self.assertEqual('apollo-services' in names, stage >= 3)
                self.assertEqual('loki' in names, stage >= 4)
                self.assertEqual('alloy' in names, stage >= 4)
                self.assertEqual('tempo' in names, stage >= 5)
                self.assertEqual('otel-collector' in names, stage >= 5)
                previous = names


if __name__ == '__main__':
    unittest.main()
